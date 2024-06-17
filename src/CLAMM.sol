// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./interfaces/IERC20.sol";
import "./lib/Tick.sol";
import "./lib/Position.sol";
import "./lib/SafeCast.sol";

contract CLAMM {
    using SafeCast for int256;
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint128 public immutable maxLiquidityPerTick;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // whether the pool is locked
        bool unlocked;
    }

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    Slot0 public slot0;
    mapping(bytes32 => Position.Info) public positions;

    modifier lock() {
        require(slot0.unlocked, "locked");
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    constructor(address _token0, address _token1, uint24 _fee, int24 _tickSpacing) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    function initialize(uint160 sqrtPriceX96) external {
        // sqrtPriceX96 = √￣p * Q96(2^^96)
        // p = (sqrtPriceX96 / Q96) ^^ 2
        // 代币x，y，以y计价 p = y / x，假设x为eth，y为usdc，则decimals_0=1e18，则decimals_1=1e6
        // x的价格为 x = p * decimals_0 / decimals_1

        // sqrtPriceX96与Tick
        // p = (sqrtPriceX96 / Q96) ^^ 2 = 1.0001 ^^ tick
        // tick = 2log(sqrtPriceX96 / Q96) / log(1.0001)
        require(slot0.sqrtPriceX96 == 0, "already initialize");
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick, unlocked: true});
    }

    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        require(tickLower < tickUpper, "TLU");
        require(tickLower >= TickMath.MIN_TICK, "TLM");
        require(tickUpper <= TickMath.MAX_TICK, "TUM");
    }

    function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta, int24 tick)
        private
        returns (Position.Info storage position)
    {
        position = positions.get(owner, tickLower, tickUpper);

        //TODO fees
        uint256 _feeGrowthGlobal0X128 = 0;
        uint256 _feeGrowthGlobal1X128 = 0;

        //TODO fees
        position.update(liquidityDelta, 0, 0);
    }

    function _modifyPosition(ModifyPositionParams memory params)
        private
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        // return (positions[bytes32(0)], 0, 0);
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization

        position = _updatePosition(params.owner, params.tickLower, params.tickUpper, params.liquidityDelta, _slot0.tick);
    }

    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount)
        external
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        require(amount > 0, "amount <= 0");

        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: recipient,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(amount)).toInt128()
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        if (amount0 > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount1);
        }
    }
}
