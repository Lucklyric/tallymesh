#!/bin/sh
# Reruns every measurement and rewrites evidence/ and results.json. Run from this directory.
set -eu
SIZES="16 64 100 256 1024"
strip() { sed 's/'"$(printf '\033')"'\[[0-9;]*m//g'; }
mkdir -p evidence/gas-json

{ go version; forge --version; sysctl -n machdep.cpu.brand_string hw.ncpu 2>/dev/null || uname -a; grep consensys go.mod; } > evidence/environment.txt 2>&1

# 1. Circuit sweep: constraints, setup, proving, native verify. Writes generated/ and evidence/go-sweep.json.
go run . 2>&1 | strip > evidence/go-sweep.txt

# 2. Gas. One forge run per contract and test, so each gas report row holds exactly the calls of that test.
: > evidence/evm-gas.txt
for kind in ClaimProof Baseline; do
  for n in $SIZES; do
    for t in 'testClaim\(' 'testSecondClaim\('; do
      name=$(echo "$kind-$n-$t" | tr -d '\\(')
      echo "### $kind N=$n $t" >> evidence/evm-gas.txt
      forge test --offline --match-contract "^${kind}${n}Test\$" --match-test "$t" --gas-report | strip >> evidence/evm-gas.txt
      forge test --offline --match-contract "^${kind}${n}Test\$" --match-test "$t" --gas-report --json > "evidence/gas-json/$name.json"
    done
  done
done

# 3. Calldata size of one claim, and the block gas limit of the test VM.
forge test --offline --match-test 'testCalldataSize' -vv | strip > evidence/evm-calldata.txt

# 4. Rejection tests, then the whole suite.
forge test --offline --match-test 'testReject' | strip > evidence/evm-rejections.txt
forge test --offline | strip > evidence/evm-all-tests.txt

uv run --no-project python collect.py
