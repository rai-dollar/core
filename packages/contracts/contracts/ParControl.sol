pragma solidity 0.8.24;

import "./v0.8.24/Dependencies/Ownable.sol";
import "./v0.8.24/Dependencies/CheckContract.sol";
import "./v0.8.24/Interfaces/IRelayer.sol";
import "./v0.8.24/Interfaces/IParControl.sol";

contract ParControl is Ownable, CheckContract, IParControl {
    // --- Authorities ---
    mapping(address => uint256) public authorities;

    modifier isAuthority() {
        require(authorities[msg.sender] == 1, "PIController/not-an-authority");
        _;
    }

    // What variable is controlled
    bytes32 public constant controlVariable = "par";

    // This value is multiplied with the error
    int256 public constant kp = 5 * 10 ** 17; // [EIGHTEEN_DECIMAL_NUMBER]

    // This value is multiplied with errorIntegral
    int256 public ki = 2 * 10 ** 13; // [EIGHTEEN_DECIMAL_NUMBER]

    // Controller output bias
    int256 public coBias = 10 ** 18; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The per second leak applied to errorIntegral before the latest error is added
    uint256 public perSecondIntegralLeak = 10 ** 18; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The maximum output value
    int256 public outputUpperBound = 10 ** 18; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The minimum output value
    int256 public outputLowerBound = 85 * 10 ** 16; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The integral term (sum of error at each update call minus the leak applied at every call)
    int256 public errorIntegral; // [TWENTY_SEVEN_DECIMAL_NUMBER]

    // The last error
    int256 public lastError; // [TWENTY_SEVEN_DECIMAL_NUMBER]

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

    // --- PI Specific Math ---
    function riemannSum(int256 x, int256 y) public pure returns (int256 z) {
        return (x + y) / 2;
    }

    /*
    * @notice Return bounded controller output
    * @param piOutput The raw output computed from the error and integral terms
    */
    function boundPiOutput(int256 piOutput) public view returns (int256) {
        int256 boundedPIOutput = piOutput;

        if (piOutput < outputLowerBound) {
            boundedPIOutput = outputLowerBound;
        } else if (piOutput > outputUpperBound) {
            boundedPIOutput = outputUpperBound;
        }

        return boundedPIOutput;
    }
    /*
    * @notice If output has reached a bound, undo integral accumulation
    * @param boundedPiOutput The bounded output computed from the error and integral terms
    * @param newErrorIntegral The updated errorIntegral, including the new area
    * @param newArea The new area that was already added to the integral that will subtracted if output has reached a bound
    */

    function clampErrorIntegral(int256 boundedPiOutput, int256 newErrorIntegral, int256 newArea)
        internal
        view
        returns (int256)
    {
        int256 clampedErrorIntegral = newErrorIntegral;

        if (both(both(boundedPiOutput == outputLowerBound, newArea < 0), errorIntegral < 0)) {
            clampedErrorIntegral = clampedErrorIntegral - newArea;
        } else if (both(both(boundedPiOutput == outputUpperBound, newArea > 0), errorIntegral > 0)) {
            clampedErrorIntegral = clampedErrorIntegral - newArea;
        }

        return clampedErrorIntegral;
    }

    /*
    * @notice Compute a new error Integral
    * @param error The system error
    */
    function getNextErrorIntegral(int256 error) public view returns (int256, int256) {
        uint256 timeElapsed = (lastUpdateTime == 0) ? 0 : block.timestamp - lastUpdateTime;
        int256 newTimeAdjustedError = riemannSum(error, lastError) * int256(timeElapsed);

        uint256 accumulatedLeak =
            (perSecondIntegralLeak == 1e27) ? TWENTY_SEVEN_DECIMAL_NUMBER : rpower(perSecondIntegralLeak, timeElapsed, TWENTY_SEVEN_DECIMAL_NUMBER);
        int256 leakedErrorIntegral = int256(accumulatedLeak) * errorIntegral / int256(TWENTY_SEVEN_DECIMAL_NUMBER);

        return (leakedErrorIntegral + newTimeAdjustedError, newTimeAdjustedError);
    }

    /*
    * @notice Apply Kp to the error and Ki to the error integral(by multiplication) and then sum P and I
    * @param error The system error TWENTY_SEVEN_DECIMAL_NUMBER
    * @param errorIntegral The calculated error integral TWENTY_SEVEN_DECIMAL_NUMBER
    * @return totalOutput, pOutput, iOutput TWENTY_SEVEN_DECIMAL_NUMBER
    */
    function getRawPiOutput(int256 error, int256 errorI) public view returns (int256, int256, int256) {
        // output = P + I = Kp * error + Ki * errorI
        int256 pOutput = error * int256(kp) / int256(EIGHTEEN_DECIMAL_NUMBER);
        int256 iOutput = errorI * int256(ki) / int256(EIGHTEEN_DECIMAL_NUMBER);
        return (coBias + pOutput + iOutput, pOutput, iOutput);
    }

    /*
    * @notice Process a new error and return controller output
    * @param error The system error TWENTY_SEVEN_DECIMAL_NUMBER
    */
    function update(int256 error) external isAuthority returns (int256, int256, int256) {
        require(block.timestamp > lastUpdateTime, "PIController/wait-longer");

        (int256 newErrorIntegral, int256 newArea) = getNextErrorIntegral(error);

        (int256 piOutput, int256 pOutput, int256 iOutput) = getRawPiOutput(error, newErrorIntegral);

        int256 boundedPiOutput = boundPiOutput(piOutput);

        // If output has reached a bound, undo integral accumulation
        errorIntegral = clampErrorIntegral(boundedPiOutput, newErrorIntegral, newArea);

        lastUpdateTime = block.timestamp;
        lastError = error;

        return (boundedPiOutput, pOutput, iOutput);
    }
    /*
    * @notice Compute and return the output given an error
    * @param error The system error
    */

    function getNextPiOutput(int256 error) public view returns (int256, int256, int256) {
        (int256 newErrorIntegral,) = getNextErrorIntegral(error);
        (int256 piOutput, int256 pOutput, int256 iOutput) = getRawPiOutput(error, newErrorIntegral);
        int256 boundedPiOutput = boundPiOutput(piOutput);

        return (boundedPiOutput, pOutput, iOutput);
    }

    /*
    * @notice Returns the time elapsed since the last update call
    */
    function elapsed() external view returns (uint256) {
        return (lastUpdateTime == 0) ? 0 : block.timestamp - lastUpdateTime;
    }
}
