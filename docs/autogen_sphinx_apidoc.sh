#!/bin/bash

## This cleans the current sphinx documentation and autogenerates
## new sphinx documentation.

set -ex

SPHINX_DIR=.
SPHINX_SOURCE_DIR=$SPHINX_DIR/source
SPHINX_AUTODOC_DIR=$SPHINX_SOURCE_DIR/autodocs
SOURCE_DIR=../src

# remove previous autodocs
rm -rf $SPHINX_AUTODOC_DIR/*

# generate the autodoc stuff
# -f: overwrite files if necessary (even though just deleted directory above!)
# -e: put each module file in its own page
# exclude the test directories
TEST_PATHS=`find ${SOURCE_DIR} -name tests`
sphinx-apidoc -o $SPHINX_AUTODOC_DIR $SOURCE_DIR -f -e -d 3 ${TEST_PATHS}

