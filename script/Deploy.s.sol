// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";
import {MiniFactory} from "../src/MiniFactory.sol";
import {MiniRouter} from "../src/MiniRouter.sol";

/// Deploys the same setup as the tests to a local anvil node, so you can swap by hand with `cast`.
/// The deployer becomes the LP and also gets 10,000 USDC to swap with.
contract Deploy is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        Token usdc = new Token("USD Coin", "USDC");
        Token weth = new Token("Wrapped Ether", "WETH");
        MiniFactory factory = new MiniFactory();
        MiniRouter router = new MiniRouter(factory);

        usdc.mint(me, 2_010_000e18);
        weth.mint(me, 1_000e18);
        usdc.approve(address(router), 2_000_000e18);
        weth.approve(address(router), 1_000e18);
        router.addLiquidity(address(weth), address(usdc), 1_000e18, 2_000_000e18, me);

        vm.stopBroadcast();

        console2.log("USDC   ", address(usdc));
        console2.log("WETH   ", address(weth));
        console2.log("factory", address(factory));
        console2.log("router ", address(router));
        console2.log("pair   ", factory.getPair(address(weth), address(usdc)));
    }
}
