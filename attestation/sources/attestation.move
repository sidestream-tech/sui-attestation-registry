module attestation::attestation;

use sui::display::{Self};
use sui::package::{Self, Publisher};
use std::ascii::{String};
use sui::table::{Self, Table};
use std::type_name::{get as get_type_name};
use sui::event::{Self};

/// Not a valid owner of the publisher object
const EInvalidPublisher: u64 = 1;
/// Attestation type of type T was not registered
const EUnknownAttestationType: u64 = 2;
/// Attestation type registered as non-revocable
const ENotRevocableType: u64 = 3;
/// Attestation with this ID was already revoked
const EAttestationAlreadyRevoked: u64 = 4;

/// Shared registry object
public struct Registry has key {
    id: UID,
    publisher: Publisher,
    is_revocable_type: Table<String, bool>,
    is_revoked: Table<ID, bool>,
}

/// Attestation type
public struct AttestationType has key {
    id: UID,
    is_revocable: bool,
    type_name: String,
}

/// Meta attestation type
public struct Attestation<T: store> has key {
    id: UID,
    to: address,
    author: address,
    data: T,
}

/// Event emitted when an Attestation is created
public struct AttestationCreated has copy, drop {
    id: ID,
    to: address,
    author: address,
}

/// Event emitted when an Attestation is revoked
public struct AttestationRevoked has copy, drop {
    id: ID,
    to: address,
    author: address,
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
        is_revocable_type: table::new<String, bool>(ctx),
        is_revoked: table::new<ID, bool>(ctx),
    };

    transfer::share_object(registry);
}

/// Register attestation type and its Display
public fun register_type<T: key + store>(
    registry: &mut Registry,
    publisher: &Publisher,
    is_revocable: bool,
    fields: vector<std::string::String>,
    values: vector<std::string::String>,
    ctx: &mut TxContext,
) {
    // Ensure `T` type belongs to the provided `publisher`
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    // Add type to the registry if it wasn't already
    let type_name = get_type_name<T>().into_string();
    assert!(table::contains(&registry.is_revocable_type, type_name), EUnknownAttestationType);
    table::add(&mut registry.is_revocable_type, type_name, is_revocable);

    // Create and freeze newly registered type
    let attestation_type = AttestationType {
        id: object::new(ctx),
        is_revocable,
        type_name,
    };
    transfer::freeze_object(attestation_type);

    // Create and freeze Display for the type
    let typeDisplay = display::new_with_fields<Attestation<T>>(&registry.publisher, fields, values, ctx);
    transfer::public_freeze_object(typeDisplay);
}

/// Create attestation
public fun attest<T: key + store>(
    registry: &Registry,
    to: address,
    data: T,
    ctx: &mut TxContext,
) {
    // Abort if the type was not previosly created via `register_type`
    let type_name = get_type_name<T>().into_string();
    assert!(table::contains(&registry.is_revocable_type, type_name), EUnknownAttestationType);

    // Create and send over the attestation
    let sender = ctx.sender();
    let attestation = Attestation {
        id: object::new(ctx),
        to: to,
        author: sender,
        data,
    };
    event::emit(AttestationCreated {
        id: object::id(&attestation),
        to: to,
        author: sender,
    });
    transfer::transfer(attestation, to);
}

/// Revoke attestation
public fun revoke<T: key + store>(
    registry: &mut Registry,
    attestation: &mut Attestation<T>,
    ctx: &mut TxContext,
) {
    // Abort if the type was not previosly created via `register_type`
    let type_name = get_type_name<T>().into_string();
    assert!(table::contains(&registry.is_revocable_type, type_name), EUnknownAttestationType);

    // Abort if non-revocable type
    let is_revocable_type = table::borrow(&registry.is_revocable_type, type_name);
    assert!(is_revocable_type == true, ENotRevocableType);

    // Abort if already revoked
    let is_revoked = table::borrow(&registry.is_revoked, object::id(attestation));
    assert!(is_revoked == true, EAttestationAlreadyRevoked);

    // Set is_revoked flag
    table::add(&mut registry.is_revoked, object::id(attestation), true);

    // Emit
    event::emit(AttestationRevoked {
        id: object::id(attestation),
        to: attestation.to,
        author: attestation.author,
        revoked_by: ctx.sender(),
    });
}
