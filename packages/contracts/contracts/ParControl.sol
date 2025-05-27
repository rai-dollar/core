pragma solidity 0.8.24;

import "./v0.8.24/Dependencies/Ownable.sol";
import "./v0.8.24/Dependencies/CheckContract.sol";
import "./v0.8.24/Interfaces/IRelayer.sol";
import "./v0.8.24/Interfaces/IParControl.sol";

contract ParControl is Ownable, CheckContract, IParControl {

    // What variable is controlled
    bytes32 public constant controlVariable = "par";

    // This value is multiplied with the error
    int256 public constant KP = 5 * 10 ** 17; // [EIGHTEEN_DECIMAL_NUMBER]

    // This value is multiplied with errorIntegral
    int256 public constant KI = 2 * 10 ** 13; // [EIGHTEEN_DECIMAL_NUMBER]

    // Factor to weaken output when par > 10**18
    int256 public constant POSITIVE_CONTROL_REDUCTION = 4; // [EIGHTEEN_DECIMAL_NUMBER]

    // Controller output bias
    int256 public constant CO_BIAS = 10 ** 18; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The per second leak applied to errorIntegral before the latest error is added
    uint256 public constant PER_SECOND_INTEGRAL_LEAK = 10 ** 18; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The maximum output value, $1.00
    int256 public constant OUTPUT_UPPER_BOUND = 115 * 10 ** 16; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The minimum output value, $0.85
    int256 public constant OUTPUT_LOWER_BOUND = 85 * 10 ** 16; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The max delta per hour, $0.01
    uint256 public constant MAX_DELTA_PER_HOUR = 10 ** 16; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The integral term (sum of error at each update call minus the leak applied at every call)
    int256 public errorIntegral; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The last error
    int256 public lastError; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The last output
    int256 public lastOutput; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // Timestamp of the last update
    uint256 public lastUpdateTime; // [timestamp]

    // Address that can update controller
    IRelayer public relayer;

    uint256 internal constant TWENTY_SEVEN_DECIMAL_NUMBER = 10 ** 27;
    uint256 internal constant EIGHTEEN_DECIMAL_NUMBER = 10 ** 18;

    event RelayerAddressChanged(address _relayerAddress);

    function setAddresses(
        address _relayerAddress
    )
        external
        override
        onlyOwner
    {
        checkContract(_relayerAddress);
        relayer = IRelayer(_relayerAddress);
        emit RelayerAddressChanged(_relayerAddress);

        _renounceOwnership();
    }

    function _requireCallerIsRelayer() internal view {
        require(msg.sender == address(relayer), "RateControl: Caller is not the Relayer contract");
    }


    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
        return x && y;
    }

    function rpower(uint256 x, uint256 n, uint256 base) public pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := base }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := base }
                default { z := x }
                let half := div(base, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    function riemannSum(int256 x, int256 y) public pure returns (int256 z) {
        return (x + y) / 2;
    }

    function max(int256 a, int256 b) internal pure returns (int256) {
        return a >= b ? a : b;
    }
    
    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /**
     * @notice Bounds the raw PI-controller output by both
     *         (a) absolute limits  and  (b) maximum slew-rate,
     *         and clamps the error-integral once if a bound is hit.
     *
     * @param piOutput       Raw   P + I output for this step
     * @param errorIntegral  Current accumulated integral term
     * @param newArea        Signed area added to the integral this step
     * @param timeElapsed    Seconds since the previous update
     *
     * @return boundedOutput   Output after both bounds are applied
     * @return clampedIntegral Possibly-clamped integral term
     */
    function boundAndClampPiOutput(
        int256 piOutput,
        int256 errorIntegral,
        int256 newArea,
        uint256 timeElapsed 
    )
        public
        view
        returns (int256 boundedOutput, int256 clampedIntegral)
    {
        boundedOutput   = piOutput;
        clampedIntegral = errorIntegral;

        /* ── compute the per-step Δ envelope ───────────────────────────── */
        int256 maxDelta = int256(MAX_DELTA_PER_HOUR * timeElapsed / 3600);
        int256 upperBound = int256(min(OUTPUT_UPPER_BOUND, lastOutput + maxDelta));
        int256 lowerBound = int256(max(OUTPUT_LOWER_BOUND, lastOutput - maxDelta));

        /* ── apply bounds & optional integral clamp ────────────────────── */
        if (piOutput < lowerBound) {
            boundedOutput = lowerBound;
            if (newArea < 0 && errorIntegral < 0) {
                clampedIntegral -= newArea;
            }
        } else if (piOutput > upperBound) {
            boundedOutput = upperBound;
            if (newArea > 0 && errorIntegral > 0) {
                clampedIntegral -= newArea;
            }
        }
    }

    /*
    * @notice Compute a new error Integral
    * @param error The system error
    */
    function getNextErrorIntegral(int256 error, uint256 timeElapsed) public view returns (int256, int256) {
        // One first update, don't accumulate error in integral
        if (lastUpdateTime == 0) {
            return (0, 0);
        }

        int256 newTimeAdjustedError = riemannSum(error, lastError) * int256(timeElapsed);

        uint256 accumulatedLeak =
            (PER_SECOND_INTEGRAL_LEAK == 1e27) ? TWENTY_SEVEN_DECIMAL_NUMBER : rpower(PER_SECOND_INTEGRAL_LEAK, timeElapsed, TWENTY_SEVEN_DECIMAL_NUMBER);
        int256 leakedErrorIntegral = int256(accumulatedLeak) * errorIntegral / int256(TWENTY_SEVEN_DECIMAL_NUMBER);

        return (leakedErrorIntegral + newTimeAdjustedError, newTimeAdjustedError);
    }

    /*
    * @notice Apply Kp to the error and Ki to the error integral(by multiplication) and then sum P and I
    * @param error The system error TWENTY_SEVEN_DECIMAL_NUMBER
    * @param errorIntegral The calculated error integral TWENTY_SEVEN_DECIMAL_NUMBER
    * @return totalOutput, pOutput, iOutput TWENTY_SEVEN_DECIMAL_NUMBER
    */
    function getRawPiOutput(int256 error, int256 errorI) public view returns (int256, int256) {
        // output = P + I = Kp * error + Ki * errorI
        int256 pOutput = error * int256(KP) / int256(EIGHTEEN_DECIMAL_NUMBER);
        int256 iOutput = errorI * int256(KI) / int256(EIGHTEEN_DECIMAL_NUMBER);
        return (pOutput, iOutput);
    }


    function _reduceOutput(int256 piOutput) internal pure returns (int256) {
        // Weaken par output in the positive direction when par > $1
        if (piOutput > 0) {
            return piOutput / POSITIVE_CONTROL_REDUCTION;
        }

        return piOutput;
    }

    /*
    * @notice Process a new error and return controller output
    * @param error The system error TWENTY_SEVEN_DECIMAL_NUMBER
    */
    function update(int256 error) external returns (int256, int256, int256) {
        _requireCallerIsRelayer();
        uint256 timeElapsed = block.timestamp - lastUpdateTime;

        //require(block.timestamp > lastUpdateTime, "PIController/wait-longer");

        (int256 newErrorIntegral, int256 newArea) = getNextErrorIntegral(error, timeElapsed);

        (int256 pOutput, int256 iOutput) = getRawPiOutput(error, newErrorIntegral);

        int256 piOutput = pOutput + iOutput;

        piOutput = _reduceOutput(piOutput);

        //int256 boundedPiOutput = boundPiOutput(CO_BIAS + piOutput);

        // If output has reached a bound, undo integral accumulation
        //errorIntegral = clampErrorIntegral(boundedPiOutput, newErrorIntegral, newArea, timeElapsed);

        int256 boundedPiOutput;
        (boundedPiOutput, errorIntegral) = boundAndClampPiOutput(CO_BIAS + piOutput, newErrorIntegral, newArea, timeElapsed);

        lastUpdateTime = block.timestamp;
        lastError = error;
        lastOutput = boundedPiOutput;

        return (boundedPiOutput, pOutput, iOutput);
    }
    /*
    * @notice Compute and return the output given an error
    * @param error The system error
    */
    function getNextPiOutput(int256 error, uint256 timeElapsed) public view returns (int256, int256, int256) {
        (int256 newErrorIntegral, int256 newArea) = getNextErrorIntegral(error, timeElapsed);
        (int256 pOutput, int256 iOutput) = getRawPiOutput(error, newErrorIntegral);
        int256 piOutput = pOutput + iOutput;

        piOutput = _reduceOutput(piOutput);

        //int256 boundedPiOutput = boundPiOutput(CO_BIAS + piOutput);
        int256 boundedPiOutput;
        (boundedPiOutput,) = boundAndClampPiOutput(CO_BIAS + piOutput, newErrorIntegral, newArea, timeElapsed);

        return (boundedPiOutput, pOutput, iOutput);
    }

    /*
    * @notice Returns the time elapsed since the last update call
    */
    function elapsed() external view returns (uint256) {
        return (lastUpdateTime == 0) ? 0 : block.timestamp - lastUpdateTime;
    }
}
