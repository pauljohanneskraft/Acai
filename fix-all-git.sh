#!/bin/bash
git config --global --replace-all safe.bareRepository all
find /home/runner -name "config" -path "*/.git/*" -type f -exec grep -H "bare = true" {} \; | while read -r file; do
    dir=$(dirname "$file")
    git config --global --add safe.directory "$dir"
    git config --global --add safe.directory $(dirname "$dir")
done
