// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////
    // Constructor Tests /////
    //////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPricefeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////
    // Price Tests /////
    ////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether; // 100 ether here actually just refers to 100*1e18. Doing this to avoid decimals.
        // $2000 /ETH, $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////
    // depositCollateral Tests /////
    ////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // Test 1
    function testDepositCollateralEmitsCollateralDepositedEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // no test for btc?

    ///////////////////////
    // mintDsc Tests /////
    //////////////////////

    // Test 2
    function testDSCMintedIsCorrectlyAddedToMintersBalance()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(dsce.getDSCMinted(USER), AMOUNT_COLLATERAL);
    }

    ///////////////////////
    // liquidate Tests ////
    //////////////////////

    // Test 3 (WIP)

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();
        _;
    }

    function testLiquidateFunctionRevertsIfUserHealthFactorIsAboveMinHealthFactor()
        public
        depositedCollateralAndMintedDsc
    {
        // who's supposed to call this function to mint weth to liquidator's address?
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        // Liquidator approve dsce contract to transfer weth
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_TO_COVER,
            AMOUNT_TO_MINT
        );
        // Liquidator is approving dsce to transfer dsc tokens on behalf of liquidator
        // Need this line because liquidator is spending dsc (to help repay the user's debt) to liquidate the "user" to receive his collateral
        dsc.approve(address(dsce), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_TO_MINT);

        vm.stopPrank();
    }

    // function liquidate(
    //     address collateral,
    //     address user,
    //     uint256 debtToCover
    // ) external moreThanZero(debtToCover) nonReentrant {
    //     // need to check health factor of the user
    //     uint256 startingUserHealthFactor = _healthFactor(user);
    //     if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
    //         revert DSCEngine__HealthFactorOk();
    //     }
    //     // We want to burn their DSC "debt"
    //     // And take their collateral
    //     // Bad user: $140 ETH, $100 DSC
    //     // debtToCover = $100
    //     // $100 of DSC == ??? ETH?
    //     // 0.05 ETH
    //     uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
    //         collateral,
    //         debtToCover
    //     );
    //     // And give them a 10% bonus
    //     // So we are giving the liquidator $110 of WETH for 100 DSC
    //     // We should implememnt a feature to liquidate in the event the protocol is insolvent
    //     // And sweep extra amounts into a treasury

    //     // 0.05 eth * .1 = 0.005. Getting 0.055 ETH
    //     uint256 bonusCollateral = (tokenAmountFromDebtCovered *
    //         LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
    //     uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
    //         bonusCollateral;
    //     // We need to burn the dsc
    //     _burnDsc(debtToCover, user, msg.sender);

    //     uint256 endingUserHealthFactor = _healthFactor(user);
    //     if (endingUserHealthFactor <= startingUserHealthFactor) {
    //         revert DSCEngine__HealthFactorNotImproved();
    //     }
    //     // call revert if by paying for the liquidation, the msg.sender's health factor
    //     // actually worsened
    //     _revertIfHealthFactorIsBroken(msg.sender);
    // }

    ///////////////////////
    // Price Tests    ////
    /////////////////////

    // Test 5
    function testGetTokenAmountFromUsdIsAccurate() public {}

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // price of ETH (token)
        // $/ETH ETH??
        // $2000 / ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e10)
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
}
