#!/bin/bash
git config --global --unset-all safe.bareRepository
git config --system --unset-all safe.bareRepository
git config --local --unset-all safe.bareRepository

git config --global safe.bareRepository all
git config --system safe.bareRepository all
