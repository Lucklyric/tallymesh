// code/contracts/eval/scripts/lib/EvalCsv.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

/// @notice CSV-row formatting helpers for eval scripts. All eval CSVs share
/// the convention: first row is the header; each subsequent row is one
/// measurement. Gas values are in raw opcode-gas units (no tx overhead).
library EvalCsv {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function writeHeader(string memory path, string memory header) internal {
        vm.writeFile(path, string.concat(header, "\n"));
    }

    function appendRow(string memory path, string memory row) internal {
        vm.writeLine(path, row);
    }

    function csvRow2(string memory a, uint256 b) internal pure returns (string memory) {
        return string.concat(a, ",", vm.toString(b));
    }

    function csvRow3(string memory a, string memory b, uint256 c) internal pure returns (string memory) {
        return string.concat(a, ",", b, ",", vm.toString(c));
    }

    function csvRow4(string memory a, string memory b, uint256 c, uint256 d) internal pure returns (string memory) {
        return string.concat(a, ",", b, ",", vm.toString(c), ",", vm.toString(d));
    }
}
