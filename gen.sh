#!/bin/bash

set -eo pipefail

cd files
getfacl -RPn . > ../attr/acl.txt
getfattr -dhRP -m- . > ../attr/xattr.txt
cd ..

ls -al attr/acl.txt attr/xattr.txt

