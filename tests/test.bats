#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  # Override this variable for your add-on:
  export GITHUB_REPO=tyler36/ddev-fakecloud

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"

  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success

  run ddev start -y
  assert_success
}

health_checks() {
  run ddev exec curl http://fakecloud:4566/_fakecloud/health
  assert_output --partial '"status":"ok"'
}

file_upload_check() {
  # Create a bucket
  export BUCKET="s3://test-bucket"
  run ddev fakecloud s3 mb "${BUCKET}"
  assert_success

  # Create and upload file
  export TEST_DATA="A simple test file"
  echo "${TEST_DATA}" > fakecloud-example.txt
  run ddev fakecloud s3 cp fakecloud-example.txt "${BUCKET}/fakecloud-example.txt"
  assert_success

  # Confirm the destination file does not already exist before copying
  run test ! -e fakecloud-pulled.txt
  assert_success

  # Copy file from bucket
  run ddev fakecloud s3 cp "${BUCKET}/fakecloud-example.txt" fakecloud-pulled.txt
  assert_success

  # Asset pulled file contains TEST_DATA
  run cat fakecloud-pulled.txt
  assert_success
  assert_output --partial "${TEST_DATA}"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success

  run ddev restart -y
  assert_success
  health_checks
  file_upload_check
}

@test "aws command is available" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success

  run ddev restart -y
  assert_success
  health_checks

  run ddev aws help
  assert_success
  assert_output --partial "usage"
  assert_output --partial "help"
}

@test "fakecloud command is available" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success

  run ddev restart -y
  assert_success
  health_checks

  # Confirm main command works
  run ddev fakecloud help
  assert_success
  assert_output --partial "aws [options] <command> <subcommand> [parameters]"

  # Confirm short-hand alias works
  run ddev fc help
  assert_success
  assert_output --partial "aws [options] <command> <subcommand> [parameters]"

  # Confirm secondary aliases works
  run ddev aws-fake help
  assert_success
  assert_output --partial "aws [options] <command> <subcommand> [parameters]"
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success

  run ddev restart -y
  assert_success
  health_checks
  file_upload_check
}
