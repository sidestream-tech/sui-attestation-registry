module attestation::attestation;

use sui::display::{Self};
use sui::package::{Self, Publisher};
use std::ascii::{String};
use std::type_name::{get as get_type_name};

/// Not a valid owner of the publisher object
const EInvalidPublisher: u64 = 1;
/// Attestation type of type T was not registered
const EUnknownAttestationType: u64 = 2;
/// Only authors can revoke their attestations
const EAttestationRevokeCapMismatch: u64 = 3;

/// Shared registry object
public struct Registry has key {
    id: UID,
    publisher: Publisher,
}

/// Attestation type
public struct AttestationType has key {
    id: UID,
    type_name: String,
    publisher: Publisher,
}

/// Meta object holding attestation data
public struct Attestation<T: store> has key {
    id: UID,
    receiver: address,
    created_by: address,
    data: T,
}

/// Object returned when attestation is created
public struct RevokeCap has key, store {
    id: UID,
    attestation: ID,
}

/// Object sent to receiver when original attestation is revoked
public struct Revocation has key {
    id: UID,
    receiver: address,
    revoked_by: address,
    attestation: ID,
}

/// OTW to claim publisher
public struct ATTESTATION has drop {}

/// Initilise the module by creating shared Registry object
fun init(otw: ATTESTATION, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let registry = Registry {
        id: object::new(ctx),
        publisher,
    };

    transfer::share_object(registry);
}

/// Register attestation type and its Display
#[allow(lint(freeze_wrapped))]
public fun register_type<T: key + store>(
    publisher: Publisher,
    fields: vector<std::string::String>,
    values: vector<std::string::String>,
    registry: &mut Registry,
    ctx: &mut TxContext,
) {
    // Ensure `T` type belongs to the provided `publisher`
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    // Create and freeze newly registered type
    let attestation_type = AttestationType {
        id: object::new(ctx),
        type_name: get_type_name<T>().into_string(),
        publisher,
    };
    transfer::freeze_object(attestation_type);

    // Create and freeze Display for the type
    let mut typeDisplay = display::new_with_fields<Attestation<T>>(&registry.publisher, fields, values, ctx);
    typeDisplay.update_version();
    transfer::public_freeze_object(typeDisplay);
}

/// Create attestation
public fun attest<T: key + store>(
    data: T,
    receiver: address,
    attestation_type: &AttestationType,
    ctx: &mut TxContext,
): RevokeCap {
    // Abort if the type was not previosly created via `register_type`
    let type_name = get_type_name<T>().into_string();
    assert!(attestation_type.type_name == type_name, EUnknownAttestationType);

    // Create attestation
    let attestation = Attestation {
        id: object::new(ctx),
        created_by: ctx.sender(),
        receiver,
        data,
    };

    // Create revocation capability
    let revoke_cap = RevokeCap {
        id: object::new(ctx),
        attestation: object::id(&attestation),
    };

    // Send attestation to receiver
    transfer::transfer(attestation, receiver);

    // Return revocation capability
    revoke_cap
}

/// Revoke attestation
public fun revoke<T: key + store>(
    attestation: &Attestation<T>,
    revoke_cap: RevokeCap,
    ctx: &mut TxContext,
): RevokeCap {
    let attestation_id = object::id(attestation);
    
    // Abort if revoke_cap from a different attestation
    assert!(revoke_cap.attestation == attestation_id, EAttestationRevokeCapMismatch);

    // Create and send over the revocation
    let revocation = Revocation {
        id: object::new(ctx),
        receiver: attestation.receiver,
        revoked_by: ctx.sender(),
        attestation: attestation_id,
    };
    transfer::transfer(revocation, attestation.receiver);

    // Return revocation capability back
    revoke_cap
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(ATTESTATION {}, ctx)
}
