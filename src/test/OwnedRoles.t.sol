// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "./utils/mocks/MockOwnedRoles.sol";

contract OwnedRolesTest is Test {
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    event OwnershipHandoverProposed(address indexed newOwner);

    event OwnershipHandoverCanceled();

    event RolesUpdated(address indexed user, uint256 indexed roles);

    MockOwnedRoles mockOwnedRoles;

    function setUp() public {
        mockOwnedRoles = new MockOwnedRoles();
    }

    function testInitializeOwnerDirect() public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(0), address(1));
        mockOwnedRoles.initializeOwnerDirect(address(1), 1);
    }

    function testSetOwnerDirect(address newOwner, uint256 brutalizer) public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), newOwner);
        mockOwnedRoles.setOwnerDirect(newOwner, brutalizer);
        assertEq(mockOwnedRoles.owner(), newOwner);
    }

    function testSetOwnerDirect() public {
        testSetOwnerDirect(address(1), 0);
    }

    function testRenounceOwnership() public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), address(0));
        mockOwnedRoles.renounceOwnership();
        assertEq(mockOwnedRoles.owner(), address(0));
    }

    function testTransferOwnership(
        address newOwner,
        bool setNewOwnerToZeroAddress,
        bool callerIsOwner
    ) public {
        assertEq(mockOwnedRoles.owner(), address(this));

        vm.assume(newOwner != address(this));

        if (newOwner == address(0) || setNewOwnerToZeroAddress) {
            newOwner = address(0);
            vm.expectRevert(OwnedRoles.NewOwnerIsZeroAddress.selector);
        } else if (callerIsOwner) {
            vm.expectEmit(true, true, true, true);
            emit OwnershipTransferred(address(this), newOwner);
        } else {
            vm.prank(newOwner);
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
        }

        mockOwnedRoles.transferOwnership(newOwner);

        if (newOwner != address(0) && callerIsOwner) {
            assertEq(mockOwnedRoles.owner(), newOwner);
        }
    }

    function testTransferOwnership() public {
        testTransferOwnership(address(1), false, true);
    }

    function testHandoverOwnership(
        address newOwner,
        bool proposerIsOwner,
        bool cancelHandover,
        bool receiverIsNewOwner
    ) public {
        vm.assume(newOwner != address(this));

        if (newOwner == address(0)) {
            vm.expectRevert(OwnedRoles.NewOwnerIsZeroAddress.selector);
            mockOwnedRoles.proposeOwnershipHandover(newOwner);
            return;
        } else if (proposerIsOwner) {
            vm.expectEmit(true, true, true, true);
            emit OwnershipHandoverProposed(newOwner);
            mockOwnedRoles.proposeOwnershipHandover(newOwner);
            assertEq(mockOwnedRoles.ownershipHandoverReceiver(), newOwner);
        } else {
            vm.prank(newOwner);
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
            mockOwnedRoles.proposeOwnershipHandover(newOwner);
            return;
        }

        if (proposerIsOwner) {
            if (cancelHandover) {
                vm.expectEmit(true, true, true, true);
                emit OwnershipHandoverCanceled();
                mockOwnedRoles.cancelOwnershipHandover();
                assertEq(mockOwnedRoles.ownershipHandoverReceiver(), address(0));
                vm.expectRevert(OwnedRoles.Unauthorized.selector);
            } else if (receiverIsNewOwner) {
                vm.prank(newOwner);
                vm.expectEmit(true, true, true, true);
                emit OwnershipTransferred(address(this), newOwner);
            } else {
                vm.expectRevert(OwnedRoles.Unauthorized.selector);
            }
            mockOwnedRoles.acceptOwnershipHandover();
        }
    }

    function testHandoverOwnership() public {
        testHandoverOwnership(address(1), true, false, true);
    }

    function testGrantRoles() public {
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(address(1), 111111);
        mockOwnedRoles.grantRoles(address(1), 111111);
    }

    function testGrantAndRevokeOrRenounceRoles(
        address user,
        uint256 userBrutalizer,
        bool granterIsOwner,
        bool useRenounce,
        bool revokerIsOwner,
        uint256 rolesToGrant,
        uint256 rolesToRevoke
    ) public {
        vm.assume(user != address(this));

        uint256 rolesAfterRevoke = rolesToGrant ^ (rolesToGrant & rolesToRevoke);

        assertTrue(rolesAfterRevoke & rolesToRevoke == 0);
        assertTrue((rolesAfterRevoke | rolesToRevoke) & rolesToGrant == rolesToGrant);

        if (granterIsOwner) {
            vm.expectEmit(true, true, true, true);
            emit RolesUpdated(user, rolesToGrant);
        } else {
            vm.prank(user);
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
        }
        mockOwnedRoles.grantRoles(user, userBrutalizer, rolesToGrant);
        userBrutalizer = ~userBrutalizer;

        if (!granterIsOwner) return;

        assertEq(mockOwnedRoles.rolesOf(user), rolesToGrant);

        if (useRenounce) {
            vm.expectEmit(true, true, true, true);
            emit RolesUpdated(user, rolesAfterRevoke);
            vm.prank(user);
            mockOwnedRoles.renounceRoles(rolesToRevoke);
        } else if (revokerIsOwner) {
            vm.expectEmit(true, true, true, true);
            emit RolesUpdated(user, rolesAfterRevoke);
            mockOwnedRoles.revokeRoles(user, userBrutalizer, rolesToRevoke);
        } else {
            vm.prank(user);
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
            mockOwnedRoles.revokeRoles(user, userBrutalizer, rolesToRevoke);
            return;
        }

        assertEq(mockOwnedRoles.rolesOf(user), rolesAfterRevoke);
    }

    function testHasAllRoles(
        address user,
        uint256 userBrutalizer,
        uint256 rolesToGrant,
        uint256 rolesToGrantBrutalizer,
        uint256 rolesToCheck,
        bool useSameRoles
    ) public {
        if (useSameRoles) {
            rolesToGrant = rolesToCheck;
        }
        rolesToGrant |= rolesToGrantBrutalizer;
        mockOwnedRoles.grantRoles(user, userBrutalizer, rolesToGrant);

        bool hasAllRoles = (rolesToGrant & rolesToCheck) == rolesToCheck;
        assertEq(mockOwnedRoles.hasAllRoles(user, rolesToCheck), hasAllRoles);
    }

    function testHasAnyRole(
        address user,
        uint256 rolesToGrant,
        uint256 rolesToCheck
    ) public {
        mockOwnedRoles.grantRoles(user, rolesToGrant);
        assertEq(mockOwnedRoles.hasAnyRoleWithCheck(user, rolesToCheck), rolesToGrant & rolesToCheck != 0);
    }

    function testRolesFromOrdinals(uint8[] memory ordinals) public {
        uint256 roles;
        unchecked {
            for (uint256 i; i < ordinals.length; ++i) {
                roles |= 1 << uint256(ordinals[i]);
            }
        }
        assertEq(mockOwnedRoles.rolesFromOrdinals(ordinals), roles);
    }

    function testOrdinalsFromRoles(uint256 roles) public {
        uint8[] memory ordinals = new uint8[](256);
        uint256 n;
        unchecked {
            for (uint256 i; i < 256; ++i) {
                if (roles & (1 << i) != 0) ordinals[n++] = uint8(i);
            }
        }
        uint8[] memory results = mockOwnedRoles.ordinalsFromRoles(roles);
        assertEq(results.length, n);
        unchecked {
            for (uint256 i; i < n; ++i) {
                assertEq(results[i], ordinals[i]);
            }
        }
    }

    function testOnlyOwnerModifier(address nonOwner, bool callerIsOwner) public {
        vm.assume(nonOwner != address(this));

        if (!callerIsOwner) {
            vm.prank(nonOwner);
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
        }
        mockOwnedRoles.updateFlagWithOnlyOwner();
    }

    function testOnlyRolesModifier(
        address user,
        uint256 rolesToGrant,
        uint256 rolesToCheck
    ) public {
        mockOwnedRoles.grantRoles(user, rolesToGrant);

        if (rolesToGrant & rolesToCheck == 0) {
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
        }
        vm.prank(user);
        mockOwnedRoles.updateFlagWithOnlyRoles(rolesToCheck);
    }

    function testOnlyOwnerOrRolesModifier(
        address user,
        bool callerIsOwner,
        uint256 rolesToGrant,
        uint256 rolesToCheck
    ) public {
        vm.assume(user != address(this));

        mockOwnedRoles.grantRoles(user, rolesToGrant);

        if ((rolesToGrant & rolesToCheck == 0) && !callerIsOwner) {
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
        }
        if (!callerIsOwner) {
            vm.prank(user);
        }
        mockOwnedRoles.updateFlagWithOnlyOwnerOrRoles(rolesToCheck);
    }

    function testOnlyRolesOrOwnerModifier(
        address user,
        bool callerIsOwner,
        uint256 rolesToGrant,
        uint256 rolesToCheck
    ) public {
        vm.assume(user != address(this));

        mockOwnedRoles.grantRoles(user, rolesToGrant);

        if ((rolesToGrant & rolesToCheck == 0) && !callerIsOwner) {
            vm.expectRevert(OwnedRoles.Unauthorized.selector);
        }
        if (!callerIsOwner) {
            vm.prank(user);
        }
        mockOwnedRoles.updateFlagWithOnlyRolesOrOwner(rolesToCheck);
    }

    function testOnlyOwnerOrRolesModifier() public {
        testOnlyOwnerOrRolesModifier(address(1), false, 1, 2);
    }
}
