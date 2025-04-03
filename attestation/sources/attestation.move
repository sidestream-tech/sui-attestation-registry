module attestation::attestation;

use sui::display::{Self};
use sui::package::{Self, Publisher};
use std::ascii::{String};
use sui::table::{Self, Table};
use std::type_name::{get as get_type_name};

/// Not a valid owner of the publisher object
const EInvalidPublisher: u64 = 1;
/// Attestation type of type T was already registered
const EAlreadyRegistered: u64 = 2;
/// Attestation type of type T was not registered
const EUnknownAttestationType: u64 = 3;
/// Attestation type registered as non-revocable
const ENotRevocableType: u64 = 4;
/// Only authors can revoke their attestations
const EAttestationAuthorMismatch: u64 = 5;

/// Shared registry object
public struct Registry has key {
    id: UID,
    publisher: Publisher,
    is_registered: Table<String, bool>,
}

/// Attestation type
public struct AttestationType has key {
    id: UID,
    type_name: String,
    is_revocable: bool,
}

/// Meta attestation type
public struct Attestation<T: store> has key {
    id: UID,
    receiver: address,
    created_by: address,
    data: T,
}

// Meta revocation type
public struct Revocation has key {
    id: UID,
    receiver: address,
    revoked_by: address,
}

/// OTW to claim publisher
public struct ATTESTATION has drop {}

/// Initilise the module by creating shared Registry object
fun init(otw: ATTESTATION, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let registry = Registry {
        id: object::new(ctx),
        publisher,
        is_registered: table::new<String, bool>(ctx),
    };

    transfer::share_object(registry);
}

/// Register attestation type and its Display
public fun register_type<T: key + store>(
    publisher: &Publisher,
    is_revocable: bool,
    fields: vector<std::string::String>,
    values: vector<std::string::String>,
    registry: &mut Registry,
    ctx: &mut TxContext,
) {
    // Ensure `T` type belongs to the provided `publisher`
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    // Add type to the registry if it wasn't already
    let type_name = get_type_name<T>().into_string();
    assert!(!table::contains(&registry.is_registered, type_name), EAlreadyRegistered);
    table::add(&mut registry.is_registered, type_name, true);

    // Create and freeze newly registered type
    let attestation_type = AttestationType {
        id: object::new(ctx),
        type_name,
        is_revocable,
    };
    transfer::freeze_object(attestation_type);

    // Create and freeze Display for the type
    let typeDisplay = display::new_with_fields<Attestation<T>>(&registry.publisher, fields, values, ctx);
    transfer::public_freeze_object(typeDisplay);
}

/// Create attestation
public fun attest<T: key + store>(
    data: T,
    receiver: address,
    attestation_type: &AttestationType,
    ctx: &mut TxContext,
) {
    // Abort if the type was not previosly created via `register_type`
    let type_name = get_type_name<T>().into_string();
    assert!(attestation_type.type_name == type_name, EUnknownAttestationType);

    // Create and send over the attestation
    let created_by = ctx.sender();
    let attestation = Attestation {
        id: object::new(ctx),
        created_by,
        receiver,
        data,
    };
    transfer::transfer(attestation, receiver);
}

/// Revoke attestation
public fun revoke<T: key + store>(
    attestation: &Attestation<T>,
    attestation_type: &AttestationType,
    ctx: &mut TxContext,
) {
    // Abort if author mismatch
    assert!(attestation.created_by == ctx.sender(), EAttestationAuthorMismatch);

    // Abort if the type was not previosly created via `register_type`
    let type_name = get_type_name<T>().into_string();
    assert!(attestation_type.type_name == type_name, EUnknownAttestationType);

    // Abort if non-revocable type
    assert!(attestation_type.is_revocable == true, ENotRevocableType);

    // Create and send over the revocation
    let revocation = Revocation {
        id: object::new(ctx),
        receiver: attestation.receiver,
        revoked_by: ctx.sender(),
    };
    transfer::transfer(revocation, attestation.receiver);
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(ATTESTATION {}, ctx)
}
