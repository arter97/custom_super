#!/bin/bash

set -eo pipefail

cd files
setfacl -P --restore=../attr/acl.txt
setfattr -h --restore=../attr/xattr.txt
find * -exec ls -aldnZ {} + | grep '?'
cd ..
