// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import "forge-std/Script.sol";

contract CreateDnEnaPtHedgeLeafsScript is Script, MerkleTreeHelper {
    address public constant TODO_ADDRESS = address(0);
    // Fill these after the vaults/contracts are deployed and API calldata is verified.
    address public ethPtVault = 0x3A140976d40d4fd23579dE5BaDFE59a78a94e168;
    address public hyperEvmHedgeVault = 0x3A140976d40d4fd23579dE5BaDFE59a78a94e168;
    address public ethRawDataDecoderAndSanitizer = 0x838AfF8182E8Df0965C34ad517564e3A8e02b091;
    address public hyperEvmRawDataDecoderAndSanitizer = 0xdA43EC8EFDf9F5926B50a4f20b0550008Ac770c2;
    address public ethManagerAddress = 0xD29E5c69D11c826f36e40eB70f9Ee01BdC282E6A;
    address public hyperEvmManagerAddress = 0xD29E5c69D11c826f36e40eB70f9Ee01BdC282E6A;
    address public ethAccountantAddress = 0x962590Ec3F666e8b5CCCF599cc01335c4F561211;
    address public hyperEvmAccountantAddress = 0x962590Ec3F666e8b5CCCF599cc01335c4F561211;
    address public strategist = 0x0c6DD78B1507bbae4781ee8aed9ba529f7c0E4E3;
    address public ena = 0x57e114B691Db790C35207b2e685D4A43181e6061;
    address public sEna = 0x8bE3460A480c80728a8C4D7a5D5303c85ba7B3b9;
    address public sySena = 0xA36ECCA8B7624D224F01CD6649C8afAd3Da12C3D;
    address public ptSena = 0xb9b3a5823DfDb39389F50742eE7bB81CF0BE56cB;
    address public ytSena = 0xd29025e0665774f66355656732cBeC826d4425ab;
    address public ptSenaMarket = 0xf1e067f8334a5A21dA018A15E29CB78252190A1b;
    address public hyperEvmCcipRouter = 0x13b3332b66389B1467CA6eBd6fa79775CCeF65ec;
    address public cctpTokenMessengerV2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address public hyperEvmCctpForwarder = 0xb21D281DEdb17AE5B501F6AA8256fe38C4e45757;
    uint32 public enaPerpAssetId = 122;
    uint64 public ccipHyperEvmDestinationSelector = 2442541497099098535;

    function run() external {
        generateEthereumLeafs();
        generateHyperEvmLeafs();
    }

    function generateEthereumLeafs() public {
        leafIndex = type(uint256).max;
        setSourceChainName(mainnet);
        vm.createSelectFork(sourceChain);
        _setCommonMainnetAddresses();

        ManageLeaf[] memory leafs = new ManageLeaf[](256);

        address ethUsdc = getAddress(sourceChain, "USDC");
        _addCctpBurnLeafs(leafs, ethUsdc);

        address[] memory flyTradeTokens = new address[](2);
        flyTradeTokens[0] = ethUsdc;
        flyTradeTokens[1] = ena;
        SwapKind[] memory flyTradeKinds = new SwapKind[](2);
        flyTradeKinds[0] = SwapKind.BuyAndSell;
        flyTradeKinds[1] = SwapKind.BuyAndSell;
        _addMagpieSwapLeafs(leafs, flyTradeTokens, flyTradeKinds);

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            ena,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve sENA to spend ENA",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = sEna;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            sEna,
            false,
            "mint(uint256,address)",
            new address[](1),
            "Mint sENA to Ethereum PT vault",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;

        _addPendlePtSenaLeafs(leafs);
        _addSEnaUnwindLeafs(leafs);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        _generateLeafs("./leafs/Mainnet/DnPtSenaLeafs.json", leafs, manageTree[manageTree.length - 1][0], manageTree);
    }

    function generateHyperEvmLeafs() public {
        leafIndex = type(uint256).max;
        setSourceChainName(hyperevm);
        vm.createSelectFork(sourceChain);
        _setCommonHyperEvmAddresses();

        ManageLeaf[] memory leafs = new ManageLeaf[](128);

        _addCoreWriterUsdcDepositLeafs(leafs);

        _addDnCoreWriterLeafs(leafs);
        _addHyperEvmCctpReturnLeafs(leafs);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        _generateLeafs("./leafs/HyperEvm/DnPtSenaLeafs.json", leafs, manageTree[manageTree.length - 1][0], manageTree);
    }

    function _setCommonMainnetAddresses() internal {
        setAddress(true, mainnet, "boringVault", ethPtVault);
        setAddress(true, mainnet, "managerAddress", ethManagerAddress);
        setAddress(true, mainnet, "accountantAddress", ethAccountantAddress);
        setAddress(true, mainnet, "rawDataDecoderAndSanitizer", ethRawDataDecoderAndSanitizer);
    }

    function _setCommonHyperEvmAddresses() internal {
        setAddress(true, hyperevm, "boringVault", hyperEvmHedgeVault);
        setAddress(true, hyperevm, "managerAddress", hyperEvmManagerAddress);
        setAddress(true, hyperevm, "accountantAddress", hyperEvmAccountantAddress);
        setAddress(true, hyperevm, "rawDataDecoderAndSanitizer", hyperEvmRawDataDecoderAndSanitizer);
        setAddress(true, hyperevm, "ccipRouter", hyperEvmCcipRouter);
    }

    function _addCctpBurnLeafs(ManageLeaf[] memory leafs, address ethUsdc) internal {
        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            ethUsdc,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve TokenMessengerV2 to spend Ethereum USDC",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = cctpTokenMessengerV2;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            cctpTokenMessengerV2,
            false,
            "depositForBurnWithHook(uint256,uint32,bytes32,address,bytes32,uint256,uint32,bytes)",
            new address[](3),
            "CCTP burn Ethereum USDC to HyperCore perp via HyperEVM CctpForwarder",
            getAddress(sourceChain, "rawDataDecoderAndSanitizer")
        );
        leafs[leafIndex].argumentAddresses[0] = hyperEvmCctpForwarder;
        leafs[leafIndex].argumentAddresses[1] = ethUsdc;
        leafs[leafIndex].argumentAddresses[2] = hyperEvmCctpForwarder;
    }

    function _addPendlePtSenaLeafs(ManageLeaf[] memory leafs) internal {
        address pendleRouter = getAddress(sourceChain, "pendleRouter");
        address decoderAndSanitizer = getAddress(sourceChain, "rawDataDecoderAndSanitizer");

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            sEna,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve Pendle router to spend sENA",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = pendleRouter;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "swapExactTokenForPt(address,address,uint256,(uint256,uint256,uint256,uint256,uint256),(address,uint256,address,address,(uint8,address,bytes,bool)),(address,uint256,((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],bytes))",
            new address[](7),
            "Swap sENA for PT-sENA via Pendle API route",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = ptSenaMarket;
        leafs[leafIndex].argumentAddresses[2] = sEna;
        leafs[leafIndex].argumentAddresses[3] = sEna;
        leafs[leafIndex].argumentAddresses[4] = address(0);
        leafs[leafIndex].argumentAddresses[5] = address(0);
        leafs[leafIndex].argumentAddresses[6] = address(0);

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "swapExactPtForToken(address,address,uint256,(address,uint256,address,address,(uint8,address,bytes,bool)),(address,uint256,((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],((uint256,uint256,uint256,uint8,address,address,address,address,uint256,uint256,uint256,bytes),bytes,uint256)[],bytes))",
            new address[](5),
            "Swap PT-sENA for sENA via Pendle API route",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = ptSenaMarket;
        leafs[leafIndex].argumentAddresses[2] = sEna;
        leafs[leafIndex].argumentAddresses[3] = sEna;
        leafs[leafIndex].argumentAddresses[4] = address(0);

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            ptSena,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve Pendle router to spend PT-sENA-24SEP2026",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = pendleRouter;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "redeemPyToSy(address,address,uint256,uint256)",
            new address[](2),
            "Burn PT-sENA-24SEP2026 and YT-sENA-24SEP2026 for SY-sENA",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = ytSena;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "redeemSyToToken(address,address,uint256,(address,uint256,address,address,(uint8,address,bytes,bool)))",
            new address[](6),
            "Burn SY-sENA for sENA",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = sySena;
        leafs[leafIndex].argumentAddresses[2] = sEna;
        leafs[leafIndex].argumentAddresses[3] = sEna;
        leafs[leafIndex].argumentAddresses[4] = address(0);
        leafs[leafIndex].argumentAddresses[5] = address(0);

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            pendleRouter,
            false,
            "redeemDueInterestAndRewards(address,address[],address[],address[])",
            new address[](4),
            "Redeem due interest and rewards for ENA Pendle",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = sySena;
        leafs[leafIndex].argumentAddresses[2] = ytSena;
        leafs[leafIndex].argumentAddresses[3] = ptSenaMarket;
    }

    function _addSEnaUnwindLeafs(ManageLeaf[] memory leafs) internal {
        address decoderAndSanitizer = getAddress(sourceChain, "rawDataDecoderAndSanitizer");

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            sEna,
            false,
            "cooldownAssets(uint256)",
            new address[](0),
            "Start sENA cooldown by assets",
            decoderAndSanitizer
        );

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            sEna,
            false,
            "cooldownShares(uint256)",
            new address[](0),
            "Start sENA cooldown by shares",
            decoderAndSanitizer
        );

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            sEna, false, "unstake(address)", new address[](1), "Unstake cooled down sENA to ENA", decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
    }

    function _addDnCoreWriterLeafs(ManageLeaf[] memory leafs) internal {
        address coreWriter = getAddress(sourceChain, "coreWriter");
        address decoderAndSanitizer = getAddress(sourceChain, "rawDataDecoderAndSanitizer");

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            coreWriter,
            false,
            "sendRawAction(bytes)",
            new address[](0),
            string.concat("Place limit order for perp asset ", vm.toString(enaPerpAssetId)),
            decoderAndSanitizer
        );

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            coreWriter,
            false,
            "sendRawAction(bytes)",
            new address[](0),
            string.concat("Cancel order by OID for perp asset ", vm.toString(enaPerpAssetId)),
            decoderAndSanitizer
        );

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            coreWriter,
            false,
            "sendRawAction(bytes)",
            new address[](0),
            string.concat("Cancel order by CLOID for perp asset ", vm.toString(enaPerpAssetId)),
            decoderAndSanitizer
        );

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            coreWriter,
            false,
            "sendRawAction(bytes)",
            new address[](0),
            "Transfer USD between spot and perp on HyperCore",
            decoderAndSanitizer
        );

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            coreWriter,
            false,
            "sendRawAction(bytes)",
            new address[](0),
            string.concat("Send asset to ", vm.toString(hyperEvmHedgeVault), " subAccount ", vm.toString(address(0))),
            decoderAndSanitizer
        );
    }

    function _addHyperEvmCctpReturnLeafs(ManageLeaf[] memory leafs) internal {
        address hyperEvmUsdc = getAddress(sourceChain, "USDC");
        address decoderAndSanitizer = getAddress(sourceChain, "rawDataDecoderAndSanitizer");

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            hyperEvmUsdc,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve TokenMessengerV2 to spend HyperEVM USDC",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = cctpTokenMessengerV2;

        unchecked {
            leafIndex++;
        }
        leafs[leafIndex] = ManageLeaf(
            cctpTokenMessengerV2,
            false,
            "depositForBurn(uint256,uint32,bytes32,address,bytes32,uint256,uint32)",
            new address[](3),
            "CCTP burn HyperEVM USDC to Ethereum vault",
            decoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = ethPtVault;
        leafs[leafIndex].argumentAddresses[1] = hyperEvmUsdc;
        leafs[leafIndex].argumentAddresses[2] = address(0);
    }
}
