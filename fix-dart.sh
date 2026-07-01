#!/bin/bash
git config --global --unset safe.bareRepository || true
git config --global safe.directory '*' || true
