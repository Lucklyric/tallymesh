// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {DepositEscrow} from "../src/DepositEscrow.sol";
import {BatchSettlement} from "../src/BatchSettlement.sol";
import {DisputeManager} from "../src/DisputeManager.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";
import {RolePolicyRegistry} from "../src/RolePolicyRegistry.sol";
import {RouterRegistry} from "../src/RouterRegistry.sol";
import {BatchValidityGroth16Verifier} from "../src/zk/BatchValidityGroth16Verifier.sol";
import {CircomBatchVerifier} from "../src/zk/CircomBatchVerifier.sol";

/// @notice Deploys the full TallyMesh stack to the local broadcast target and
/// emits a JSON-formatted address book the SDK reads at integration-test time.
contract DeployLocal is Script {
    /// @dev Default chargedCeiling for the local DisputeManager. Tests may
    /// override BatchSettlement's per-receipt ceiling via setChargedCeiling.
    uint256 internal constant DEFAULT_CHARGED_CEILING = 1 ether;

    function run() external {
        vm.startBroadcast();

        ServiceRegistry serviceReg   = new ServiceRegistry();
        RolePolicyRegistry policyReg = new RolePolicyRegistry(address(serviceReg));
        RouterRegistry routerReg     = new RouterRegistry();
        DepositEscrow escrow         = new DepositEscrow();
        BatchSettlement settlement   = new BatchSettlement(address(escrow));
        DisputeManager dispute       = new DisputeManager(address(settlement), DEFAULT_CHARGED_CEILING);

        escrow.setAuthorizedSettler(address(settlement), true);
        settlement.setDisputeManager(address(dispute));

        BatchValidityGroth16Verifier g16 = new BatchValidityGroth16Verifier();
        CircomBatchVerifier circomVerifier = new CircomBatchVerifier(address(g16));
        settlement.setApprovedVerifier(address(circomVerifier), true);

        vm.stopBroadcast();

        // Emit a JSON object the SDK reads.
        string memory json = string.concat(
            "{",
              "\"ServiceRegistry\":\"",   vm.toString(address(serviceReg)),     "\",",
              "\"RolePolicyRegistry\":\"", vm.toString(address(policyReg)),     "\",",
              "\"RouterRegistry\":\"",    vm.toString(address(routerReg)),     "\",",
              "\"DepositEscrow\":\"",     vm.toString(address(escrow)),        "\",",
              "\"BatchSettlement\":\"",   vm.toString(address(settlement)),    "\",",
              "\"DisputeManager\":\"",    vm.toString(address(dispute)),       "\",",
              "\"BatchValidityGroth16Verifier\":\"", vm.toString(address(g16)), "\",",
              "\"CircomBatchVerifier\":\"", vm.toString(address(circomVerifier)), "\"",
            "}"
        );
        vm.writeFile("../sdk-ts/addresses.local.json", json);
    }
}
