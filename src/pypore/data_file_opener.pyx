"""
Created on May 23, 2013

@author: parkin1
"""
#cython: embedsignature=True

import scipy.io as sio
import numpy as np

cimport numpy as np
import os
import tables as tb

DTYPE = np.float
ctypedef np.float_t DTYPE_t

# Data types list, in order specified by the HEKA file header v2.0.
# Using big-endian.
# Code 0=uint8,1=uint16,2=uint32,3=int8,4=int16,5=int32,
#    6=single,7=double,8=string64,9=string512
encodings = [np.dtype('>u1'), np.dtype('>u2'), np.dtype('>u4'),
             np.dtype('>i1'), np.dtype('>i2'), np.dtype('>i4'),
             np.dtype('>f4'), np.dtype('>f8'), np.dtype('>S64'),
             np.dtype('>S512'), np.dtype('<u2')]

cpdef open_data(filename, decimate=False):
    """
    Opens a datafile and returns a dictionary with the data in 'data'.
    If unable to return, will return an error message.

    :param StringType filename: Filename to open.

        - Assumes '.h5' extension is Pypore HDF5 format.
        - Assumes '.log' extension is Chimera data.  Chimera data requires a '.mat'\
            file with the same name to be in the same folder.
        - Assumes '.hkd' extension is Heka data.
        - Assumes '.mat' extension is Gaby's format.

    :param BooleanType decimate: Whether or not to decimate the data. Default is False.
    :returns: DictType -- dictionary with data in the 'data' key. If there is an error, it will return a
        dictionary with 'error' key containing a String error message.
    """
    # if '.h5' in filename:
    #     return open_pypore_file(filename, decimate)
    # if '.log' in filename:
    #     return open_chimera_file(filename, decimate)
    if '.hkd' in filename:
        return open_heka_file(filename, decimate)
    elif '.mat' in filename:
        return open_gabys_file(filename, decimate)

    return {'error': 'File not specified with correct extension. Possibilities are: \'.log\', \'.hkd\''}

cpdef prepare_data_file(filename):
    """
    Opens a data file, reads relevant parameters, and returns then open file and parameters.

    :param StringType filename: Filename to open and read parameters.

        - Assumes '.h5' extension is Pypore HDF5 format.
        - Assumes '.log' extension is Chimera data.  Chimera data requires a '.mat'\
            file with the same name to be in the same folder.
        - Assumes '.hkd' extension is Heka data.
        - Assumes '.mat' extension is Gaby's format.
    
    :returns: 2 things:

        #. datafile -- already opened :py:class:`pypore.filetypes.data_file.DataFile`.
        #. params -- parameters read from the file.

        If there was an error opening the files, params will have 'error' key with string description.
    """
    # if '.h5' in filename:
    #     return prepare_pypore_file(filename)
    # if '.log' in filename:
    #     return prepare_chimera_file(filename)
    if '.hkd' in filename:
        return prepare_heka_file(filename)
    if '.mat' in filename:
        return prepare_gabys_file(filename)

    return 0, {'error': 'File not specified with correct extension. Possibilities are: \'.log\', \'.hkd\', \'.mat\''}

cpdef get_next_blocks(datafile, params, int n=1):
    """
    Gets the next n blocks (~5000 data points) of data from filename.
    
    :param DataFile datafile: An already open :py:class:`pypore.filetypes.data_file.DataFile`.
    :param DictType params: Parameters of the file, usually the ones returned from :py:func:`prepare_data_file`.

        - Assumes '.h5' extension is Pypore HDF5 format.
        - Assumes '.log' extension is Chimera data.  Chimera data requires a '.mat'\
            file with the same name to be in the same folder.
        - Assumes '.hkd' extension is Heka data.
        - Assumes '.mat' extension is Gaby's format.

    :param IntType n: Number of blocks to read and return.
    :returns: ListType<np.array> -- List of numpy arrays, one for each channel of the data.
    """
    # if '.h5' in params['filename']:
    #     return get_next_pypore_blocks(datafile, params, n)
    # if '.log' in params['filename']:
    #     return get_next_chimera_blocks(datafile, params, n)
    if '.hkd' in params['filename']:
        return get_next_heka_blocks(datafile, params, n)
    if '.mat' in params['filename']:
        return get_next_gabys_blocks(datafile, params, n)

    return 'File not specified with correct extension. Possibilities are: \'.log\', \'.hkd\''


cdef prepare_gabys_file(filename):
    """
    Implementation of :py:func:`prepare_data_file` for Gaby's .mat files.
    The file is a Matlab > 7.3 file, which is
    an HDF file and can be opened with pytables.
    """
    datafile = tb.openFile(filename, mode='r')

    group = datafile.getNode('/#refs#').b

    cdef int points_per_channel_per_block = 10000

    p = {'filetype': 'gabys',
         'dataGroup': group,
         'filename': filename, 'nextToSend': 0,  # next point we haven't sent
         'sample_rate': group.samplerate[0][0],
         'points_per_channel_per_block': points_per_channel_per_block,
         'points_per_channel_total': group.Raw[0].size}
    return datafile, p

cdef open_gabys_file(filename, decimate=False):
    f, p = prepare_gabys_file(filename)
    group = p['dataGroup']

    cdef np.ndarray data2

    cdef float sample_rate = p['sample_rate']

    if decimate:
        data2 = group.Raw[0][::5000]
        sample_rate /= 5000.
    else:
        data2 = group.Raw[0]

    specs_file = {'data': [data2], 'sample_rate': sample_rate}
    f.close()
    return specs_file

cdef get_next_gabys_blocks(datafile, params, int n):
    group = datafile.getNode('/#refs#').b

    cdef long next_to_send_2 = params['nextToSend']
    cdef long points_per_block2 = params['points_per_channel_per_block']
    cdef total_points_2 = params['points_per_channel_total']

    if next_to_send_2 >= total_points_2:
        return [group.Raw[0][next_to_send_2:].astype(DTYPE)]
    else:
        params['nextToSend'] += points_per_block2
        return [group.Raw[0][next_to_send_2:next_to_send_2 + points_per_block2].astype(DTYPE)]

cdef prepare_heka_file(filename):
    """
    Implementation of :py:func:`prepare_data_file` for Heka ".hkd" files.
    """
    f = open(filename, 'rb')
    # Check that the first line is as expected
    line = f.readline()
    if not 'Nanopore Experiment Data File V2.0' in line:
        f.close()
        return 0, {'error': 'Heka data file format not recognized.'}
    # Just skip over the file header text, should be always the same.
    while True:
        line = f.readline()
        if 'End of file format' in line:
            break

    # So now f should be at the binary data.

    # # Read binary header parameter lists
    per_file_param_list = _read_heka_header_param_list(f, np.dtype('>S64'), encodings)
    per_block_param_list = _read_heka_header_param_list(f, np.dtype('>S64'), encodings)
    per_channel_param_list = _read_heka_header_param_list(f, np.dtype('>S64'), encodings)
    channel_list = _read_heka_header_param_list(f, np.dtype('>S512'), encodings)

    # # Read per_file parameters
    per_file_params = _read_heka_header_params(f, per_file_param_list)

    # # Calculate sizes of blocks, channels, etc
    cdef long per_file_header_length = f.tell()

    # Calculate the block lengths
    cdef long per_channel_per_block_length = _get_param_list_byte_length(per_channel_param_list)
    cdef long per_block_length = _get_param_list_byte_length(per_block_param_list)

    cdef int channel_list_number = len(channel_list)

    cdef long header_bytes_per_block = per_channel_per_block_length * channel_list_number
    cdef long data_bytes_per_block = per_file_params['Points per block'] * 2 * channel_list_number
    cdef long total_bytes_per_block = header_bytes_per_block + data_bytes_per_block + per_block_length

    # Calculate number of points per channel
    cdef long filesize = os.path.getsize(filename)
    cdef long num_blocks_in_file = int((filesize - per_file_header_length) / total_bytes_per_block)
    cdef long remainder = (filesize - per_file_header_length) % total_bytes_per_block
    if not remainder == 0:
        f.close()
        return 0, {'error': 'Error, data file ends with incomplete block'}
    cdef long points_per_channel_total = per_file_params['Points per block'] * num_blocks_in_file
    cdef long points_per_channel_per_block = per_file_params['Points per block']

    p = {'filetype': 'heka',
         'per_file_param_list': per_file_param_list, 'per_block_param_list': per_block_param_list,
         'per_channel_param_list': per_channel_param_list, 'channel_list': channel_list,
         'per_file_params': per_file_params, 'per_file_header_length': per_file_header_length,
         'per_channel_per_block_length': per_channel_per_block_length,
         'per_block_length': per_block_length, 'channel_list_number': channel_list_number,
         'header_bytes_per_block': header_bytes_per_block,
         'data_bytes_per_block': data_bytes_per_block,
         'total_bytes_per_block': total_bytes_per_block, 'filesize': filesize,
         'num_blocks_in_file': num_blocks_in_file,
         'points_per_channel_total': points_per_channel_total,
         'points_per_channel_per_block': points_per_channel_per_block,
         'sample_rate': 1.0 / per_file_params['Sampling interval'],
         'filename': filename}

    return f, p

cdef open_heka_file(filename, decimate=False):
    """
    Gets data from a file generated by Ken's LabView code v2.0 for HEKA acquisition.
    Visit https://drndiclab-bkup.physics.upenn.edu/wiki/index.php/HKD_File_I/O_SubVIs
        for a description of the heka file format.
        
    Returns a dictionary with entries:
        -'data', a numpy array of the current values
        -'SETUP_ADCSAMPLERATE'
        
    Currently only works with one channel measurements
    """
    # Open the file and read all of the header parameters
    f, p = prepare_heka_file(filename)

    per_file_params = p['per_file_params']
    channel_list = p['channel_list']
    cdef long num_blocks_in_file = p['num_blocks_in_file']
    cdef long points_per_channel_total = p['points_per_channel_total']
    per_block_param_list = p['per_block_param_list']
    per_channel_param_list = p['per_channel_param_list']
    cdef long points_per_channel_per_block = p['points_per_channel_per_block']

    data = []
    cdef double sample_rate = 1.0 / per_file_params['Sampling interval']
    for _ in channel_list:
        if decimate:  # If decimating, just keep max and min value from each block
            data.append(np.empty(num_blocks_in_file * 2))
        else:
            data.append(np.empty(points_per_channel_total))  # initialize_c array

    for i in xrange(0, num_blocks_in_file):
        block = _read_heka_next_block(f, per_file_params, per_block_param_list, per_channel_param_list, channel_list,
                                      points_per_channel_per_block)
        for j in xrange(len(block)):
            if decimate:  # if decimating data, only keep max and min of each block
                data[j][2 * i] = np.max(block[j])
                data[j][2 * i + 1] = np.min(block[j])
            else:
                data[j][i * points_per_channel_per_block:(i + 1) * points_per_channel_per_block] = block[j]

    if decimate:
        sample_rate = sample_rate * 2 / per_file_params['Points per block']  # we are downsampling

    # return dictionary
    # samplerate is i [[]] because of how chimera data is returned.
    specsfile = {'data': data, 'sample_rate': sample_rate}

    return specsfile

cdef get_next_heka_blocks(datafile, params, int n):
    per_file_params = params['per_file_params']
    per_block_param_list = params['per_block_param_list']
    per_channel_param_list = params['per_channel_param_list']
    channel_list = params['channel_list']
    cdef long points_per_channel_per_block = params['points_per_channel_per_block']

    blocks = []
    cdef long totalsize = 0
    cdef long size = 0
    done = False
    for i in xrange(0, n):
        block = _read_heka_next_block(datafile, per_file_params,
                                      per_block_param_list, per_channel_param_list,
                                      channel_list, points_per_channel_per_block)
        if block[0].size == 0:
            return block
        blocks.append(block)
        size = block[0].size
        totalsize = totalsize + size
        if size < points_per_channel_per_block:  # did we reach the end?
            break

    # stitch the data together
    data = []
    index = []
    for _ in xrange(0, len(channel_list)):
        data.append(np.empty(totalsize))
        index.append(0)
    for block in blocks:
        for i in xrange(0, len(channel_list)):
            data[i][index[i]:index[i] + block[i].size] = block[i]
            index[i] = index[i] + block[i].size

    return data

cdef _read_heka_next_block(f, per_file_params, per_block_param_list, per_channel_param_list, channel_list,
                           long points_per_channel_per_block):
    """
    Reads the next block of heka data.
    Returns a dictionary with 'data', 'per_block_params', and 'per_channel_params'.
    """

    # Read block header
    per_block_params = _read_heka_header_params(f, per_block_param_list)
    if per_block_params == None:
        return [np.empty(0)]

    # Read per channel header
    per_channel_block_params = []
    for _ in channel_list:  # underscore used for discarded parameters
        channel_params = {}
        # i[0] = name, i[1] = datatype
        for i in per_channel_param_list:
            channel_params[i[0]] = np.fromfile(f, i[1], 1)[0]
        per_channel_block_params.append(channel_params)

    # Read data
    data = []
    dt = np.dtype('>i2')  # int16
    cdef np.ndarray values
    for i in xrange(0, len(channel_list)):
        values = np.fromfile(f, dt, count=points_per_channel_per_block) * per_channel_block_params[i]['Scale']
        # get rid of nan's
        #         values[np.isnan(values)] = 0
        data.append(values)

    return data

cdef long _get_param_list_byte_length(param_list):
    """
    Returns the length in bytes of the sum of all the parameters in the list.
    Here, list[i][0] = param, list[i][1] = np.dtype
    """
    cdef long sizee = 0
    for i in param_list:
        sizee = sizee + i[1].itemsize
    return sizee

cdef _read_heka_header_params(f, param_list):
    params = {}
    # pair[0] = name, pair[1] = np.datatype
    cdef np.ndarray array
    for pair in param_list:
        array = np.fromfile(f, pair[1], 1)
        if array.size > 0:
            params[pair[0]] = array[0]
        else:
            return None
    return params

cdef _read_heka_header_param_list(f, datatype, encodings):
    """
    Reads the binary parameter list of the following format:
        3 null bytes
        1 byte uint8 - how many params following
        params - 1 byte uint8 - code for datatype (eg encoding[code])
                 datatype.intemsize bytes - name the parameter
    Returns a list of parameters, with
        item[0] = name
        item[1] = numpy datatype
    """
    param_list = []
    f.read(3)  # read null characters?
    dt = np.dtype('>u1')
    cdef int num_params = np.fromfile(f, dt, 1)[0]
    for _ in xrange(0, num_params):
        type_code = np.fromfile(f, dt, 1)[0]
        name = np.fromfile(f, datatype, 1)[0].strip()
        param_list.append([name, encodings[type_code]])
    return param_list


