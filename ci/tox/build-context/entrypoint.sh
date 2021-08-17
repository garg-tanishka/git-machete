#!/bin/sh

{ [ -f setup.py ] && grep -q "name='git-machete'" setup.py; } || {
  echo "Error: the repository should be mounted as a volume under $(pwd)"
  exit 1
}

set -e -u -x

$PYTHON -m pip install --user tox

if "${CHECK_COVERAGE:-false}" = true; then
  TOXENV="pep8,py${PYTHON_VERSION/./},coverage" tox
else
  TOXENV="pep8,py${PYTHON_VERSION/./}" tox
fi

$PYTHON setup.py install --user
git machete --version
