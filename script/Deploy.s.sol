// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PhytoacousticDataset} from "../src/PhytoacousticDataset.sol";

/**
 * @title  DeployPhytoacousticDataset
 * @notice Deployment script for the Early Storehouse provenance registry.
 *
 * @dev Usage (Optimism mainnet):
 *
 *   forge script script/Deploy.s.sol:DeployPhytoacousticDataset \
 *     --rpc-url optimism --broadcast --verify
 *
 *   Dry run against a fork (no broadcast):
 *
 *   forge script script/Deploy.s.sol:DeployPhytoacousticDataset --rpc-url optimism
 *
 * Environment variables:
 *   PRIVATE_KEY  Deployer key. Local only - never commit it.
 *   OWNER        Address that will own the contract (the Gnosis Safe multisig).
 *                Defaults to the deployer address when unset.
 */
contract DeployPhytoacousticDataset is Script {
    function run() external returns (PhytoacousticDataset dataset) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envOr("OWNER", vm.addr(deployerKey));

        vm.startBroadcast(deployerKey);
        dataset = new PhytoacousticDataset(owner);
        vm.stopBroadcast();

        console2.log("PhytoacousticDataset deployed:", address(dataset));
        console2.log("Owner (should be the Gnosis Safe):", owner);
    }
}
