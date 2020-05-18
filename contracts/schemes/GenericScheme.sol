pragma solidity ^0.5.17;

import "@daostack/infra-experimental/contracts/votingMachines/IntVoteInterface.sol";
import "@daostack/infra-experimental/contracts/votingMachines/VotingMachineCallbacksInterface.sol";
import "../votingMachines/VotingMachineCallbacks.sol";


/**
 * @title GenericScheme.
 * @dev  A scheme for proposing and executing calls to an arbitrary function
 * on a specific contract on behalf of the organization avatar.
 */
contract GenericScheme is VotingMachineCallbacks, ProposalExecuteInterface {
    event NewCallProposal(
        address indexed _avatar,
        bytes32 indexed _proposalId,
        bytes   _callData,
        uint256 _value,
        string  _descriptionHash
    );

    event ProposalExecuted(
        address indexed _avatar,
        bytes32 indexed _proposalId,
        bytes _genericCallReturnValue
    );

    event ProposalExecutedByVotingMachine(
        address indexed _avatar,
        bytes32 indexed _proposalId,
        int256 _param
    );

    event ProposalDeleted(address indexed _avatar, bytes32 indexed _proposalId);

    // Details of a voting proposal:
    struct CallProposal {
        bytes callData;
        uint256 value;
        bool exist;
        bool passed;
    }

    mapping(bytes32=>CallProposal) public organizationProposals;

    address public contractToCall;

    /**
     * @dev initialize
     * @param _avatar the avatar this scheme referring to.
     * @param _votingParams genesisProtocol parameters
     * @param _addresses array of addresses
     *       addresses[0] - _daoFactory DAOFactory instance to instance a votingMachine.
     *       addresses[1] - _voteOnBehalf  parameter
     *       addresses[2] - _organization organization
     *       addresses[3] - _callbacks should fulfill voting callbacks interface
     *       addresses[4] - _authorizedToPropose only this address allow to propose (unless it is zero)
     *       addresses[5] - _stakingToken (for GenesisProtocol)
     * @param _packageVersion packageVersion to instance the votingMachine from.
     * @param _votingMachineName the votingMachine contract name.
     * @param _contractToCall the target contract this scheme will call to
     */
    function initialize(
        Avatar _avatar,
        uint256[11] calldata _votingParams,
        address[6] calldata _addresses,
        uint64[3] calldata _packageVersion,
        string calldata _votingMachineName,
        address _contractToCall
    )
    external
    {
        super._initializeGovernance(_avatar, _votingParams, _addresses, _packageVersion, _votingMachineName);
        contractToCall = _contractToCall;
    }

    /**
    * @dev execution of proposals, can only be called by the voting machine in which the vote is held.
    * @param _proposalId the ID of the voting in the voting machine
    * @param _decision a parameter of the voting result, 1 yes and 2 is no.
    * @return bool success
    */
    function executeProposal(bytes32 _proposalId, int256 _decision)
    external
    onlyVotingMachine(_proposalId)
    returns(bool) {
        CallProposal storage proposal = organizationProposals[_proposalId];
        require(proposal.exist, "must be a live proposal");
        require(proposal.passed == false, "cannot execute twice");

        if (_decision == 1) {
            proposal.passed = true;
            execute(_proposalId);
        } else {
            delete organizationProposals[_proposalId];
            emit ProposalDeleted(address(avatar), _proposalId);
        }

        emit ProposalExecutedByVotingMachine(address(avatar), _proposalId, _decision);
        return true;
    }

    /**
    * @dev execution of proposals after it has been decided by the voting machine
    * @param _proposalId the ID of the voting in the voting machine
    */
    function execute(bytes32 _proposalId) public {
        CallProposal storage proposal = organizationProposals[_proposalId];
        require(proposal.exist, "must be a live proposal");
        require(proposal.passed, "proposal must passed by voting machine");
        proposal.exist = false;
        bytes memory genericCallReturnValue;
        bool success;
        Controller controller = Controller(avatar.owner());
        (success, genericCallReturnValue) =
        controller.genericCall(contractToCall, proposal.callData, proposal.value);
        if (success) {
            delete organizationProposals[_proposalId];
            emit ProposalDeleted(address(avatar), _proposalId);
            emit ProposalExecuted(address(avatar), _proposalId, genericCallReturnValue);
        } else {
            proposal.exist = true;
        }
    }

    /**
    * @dev propose to call on behalf of the _avatar
    *      The function trigger NewCallProposal event
    * @param _callData - The abi encode data for the call
    * @param _value value(ETH) to transfer with the call
    * @param _descriptionHash proposal description hash
    * @return an id which represents the proposal
    */
    function proposeCall(bytes memory _callData, uint256 _value, string memory _descriptionHash)
    public
    returns(bytes32)
    {
        bytes32 proposalId = votingMachine.propose(2, msg.sender);

        organizationProposals[proposalId] = CallProposal({
            callData: _callData,
            value: _value,
            exist: true,
            passed: false
        });

        proposalsBlockNumber[proposalId] = block.number;

        emit NewCallProposal(address(avatar), proposalId, _callData, _value, _descriptionHash);
        return proposalId;
    }

}
