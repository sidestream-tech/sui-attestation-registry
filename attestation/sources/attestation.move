module attestation::attestation;

use std::ascii::{String};
use std::type_name::{get as get_type_name};
use sui::display::{Self};
use sui::package::{Self, Publisher};
use sui::table::{Self, Table};
use sui::bag::{Self, Bag};

/// Not a valid owner of the publisher object
const EInvalidTypePublisher: u64 = 1;
/// AttestationType does not match provided T
const EInvalidAttestationType: u64 = 2;
/// Provided publisher does not match attested receiver
const EInvalidReceiverPublisher: u64 = 3;

/// Shared registry object
public struct Registry has key {
    id: UID,
    publisher: Publisher,
    attestations: Table<address /* package */, Bag /* ID, Attestation<T> */>,
}

/// Attestation type
public struct AttestationType has key {
    id: UID,
    type_name: String,
    type_publisher: Publisher,
}

/// Meta object holding attestation data
public struct Attestation<T: store> has key, store {
    id: UID,
    receiver: address,
    created_by: address,
    revoked_by: Option<address>,
    data: T,
    is_pinned: bool,
}

/// Object returned when attestation is created
public struct RevokeCap has key, store {
    id: UID,
    receiver: address,
    attestation_id: ID,
}

/// OTW to claim publisher
public struct ATTESTATION has drop {}

/// Initilise the module by creating shared Registry object
fun init(otw: ATTESTATION, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let registry = Registry {
        id: object::new(ctx),
        publisher,
        attestations: table::new<address, Bag>(ctx),
    };

    transfer::share_object(registry);
}

/// Register attestation type and its Display
#[allow(lint(freeze_wrapped))]
public fun register_type<T: key + store>(
    type_publisher: Publisher,
    fields: vector<std::string::String>,
    values: vector<std::string::String>,
    registry: &mut Registry,
    ctx: &mut TxContext,
) {
    // Ensure `T` type belongs to the provided `publisher`
    assert!(type_publisher.from_module<T>(), EInvalidTypePublisher);

    // Create and freeze newly registered type
    let attestation_type = AttestationType {
        id: object::new(ctx),
        type_name: get_type_name<T>().into_string(),
        type_publisher,
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
    registry: &mut Registry,
    ctx: &mut TxContext,
): RevokeCap {
    // Abort if the type was not previosly created via `register_type`
    let type_name = get_type_name<T>().into_string();
    assert!(attestation_type.type_name == type_name, EInvalidAttestationType);

    // Create attestation
    let attestation = Attestation {
        id: object::new(ctx),
        created_by: ctx.sender(),
        revoked_by: option::none(),
        receiver,
        data,
        is_pinned: false,
    };
    let attestation_id = object::id(&attestation);

    // Create revocation capability
    let revoke_cap = RevokeCap {
        id: object::new(ctx),
        receiver,
        attestation_id,
    };

    // Store attestation in the registry
    if (!registry.attestations.contains(receiver)) {
        // if it's the first attestation for this package, create a new bag
        let mut package_bag = bag::new(ctx);
        package_bag.add(attestation_id, attestation);
        registry.attestations.add(receiver, package_bag);
    } else {
        // else, borrow existing bag
        let package_bag = registry.attestations.borrow_mut(receiver);
        package_bag.add(attestation_id, attestation);
    };

    // Return revocation capability
    revoke_cap
}

/// Revoke attestation (using RevokeCap)
#[allow(lint(freezing_capability))]
public fun revoke<T: key + store>(
    revoke_cap: RevokeCap,
    registry: &mut Registry,
    ctx: &mut TxContext,
) {
    let package_bag = registry.attestations.borrow_mut(revoke_cap.receiver);
    let attestation: &mut Attestation<T> = package_bag.borrow_mut(revoke_cap.attestation_id);

    // Modify attestation object
    attestation.revoked_by = option::some(ctx.sender());

    // Freeze revocation capability, since it can't be used again
    transfer::public_freeze_object(revoke_cap);
}

/// Pin attestation (using Publisher of the attestation.receiver)
public fun pin<T: key + store>(
    receiver_publisher: Publisher,
    attestation: &Attestation<T>,
    registry: &mut Registry
): Publisher {
    assert!(receiver_publisher.published_package() == attestation.receiver.to_ascii_string(), EInvalidReceiverPublisher);
    let package_bag = registry.attestations.borrow_mut(attestation.receiver);
    let attestation: &mut Attestation<T> = package_bag.borrow_mut(object::id(attestation));

    // Modify attestation object
    attestation.is_pinned = true;

    // Return provided receiver publisher
    receiver_publisher
}

// Unpin attestation (using Publisher of the attestation.receiver)
public fun unpin<T: key + store>(
    receiver_publisher: Publisher,
    attestation: &Attestation<T>,
    registry: &mut Registry
): Publisher {
    assert!(receiver_publisher.published_package() == attestation.receiver.to_ascii_string(), EInvalidReceiverPublisher);
    let package_bag = registry.attestations.borrow_mut(attestation.receiver);
    let attestation: &mut Attestation<T> = package_bag.borrow_mut(object::id(attestation));

    // Modify attestation object
    attestation.is_pinned = false;

    // Return provided receiver publisher
    receiver_publisher
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(ATTESTATION {}, ctx)
}
