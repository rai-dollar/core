pragma solidity ^0.8.24;

/**
 * @title  IOracle
 * @notice Interface for the Oracle hook contract
 */
interface IOracle {
    // --- Errors ---

    /**
     * @notice Error thrown when trying to register a hook that is already registered.
     */
    error Oracle_AlreadyRegistered();

    /**
     * @notice Error thrown when the pool was not created by the allowed factory.
     * @param pool The address of the pool.
     */
    error Oracle_PoolNotFromFactory(address pool);

    // --- Data ---

    /**
     * @notice Getter for the pool address
     * @return _pool The pool address
     */
    function pool() external view returns (address _pool);
}
