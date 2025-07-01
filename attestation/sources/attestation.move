module attestation::attestation;

use sui::display::{Self};
use sui::package::{Self, Publisher};
use sui::table::{Self, Table};
use sui::bag::{Self, Bag};

/// Not a valid owner of the publisher object
const EInvalidTypePublisher: u64 = 1;
/// Provided publisher does not match attested receiver
const EInvalidReceiverPublisher: u64 = 2;

/// Shared registry object
public struct Registry has key {
    id: UID,
    publisher: Publisher,
    attestations: Table<address /* package */, Bag /* created_by, Attestation<T> */>,
}

/// Attestation type
public struct AttestationType<phantom T: key> has key {
    id: UID,
    publisher: Publisher,
}

/// Meta object holding attestation data
public struct Attestation<T: store> has key, store {
    id: UID,
    receiver: address,
    data: T,
    created_by: address,
    revoked_by: Option<address>,
    is_pinned: bool,
}

/// Object returned when attestation is created
public struct RevokeCap has key, store {
    id: UID,
    receiver: address,
    attestation_id: ID,
    created_by: address,
}

/// OTW to claim publisher
public struct ATTESTATION has drop {}

/// Initilise the module by creating shared Registry object
fun init(otw: ATTESTATION, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let registry = Registry {
        id: object::new(ctx),
        publisher,
        attestations: table::new(ctx),
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
    let attestation_type = AttestationType<T> {
        id: object::new(ctx),
        publisher: type_publisher,
    };
    transfer::freeze_object(attestation_type);

    // Create and freeze Display for the type
    let mut type_display = display::new_with_fields<Attestation<T>>(&registry.publisher, fields, values, ctx);
    type_display.update_version();
    transfer::public_freeze_object(type_display);
}

/// Create attestation
public fun attest<T: key + store>(
    data: T,
    receiver: address,
    _: &AttestationType<T>,
    registry: &mut Registry,
    ctx: &mut TxContext,
): RevokeCap {
    // Create attestation
    let attestation = Attestation {
        id: object::new(ctx),
        receiver,
        data,
        created_by: ctx.sender(),
        revoked_by: option::none(),
        is_pinned: false,
    };

    // Create revocation capability
    let revoke_cap = RevokeCap {
        id: object::new(ctx),
        receiver,
        attestation_id: object::id(&attestation),
        created_by: ctx.sender(),
    };

    // Store attestation in the registry
    if (!registry.attestations.contains(receiver)) {
        // if it's the first attestation for this package, create a new bag
        let mut package_bag = bag::new(ctx);
        package_bag.add(ctx.sender(), attestation);
        registry.attestations.add(receiver, package_bag);
    } else {
        // else, borrow existing bag
        let package_bag = registry.attestations.borrow_mut(receiver);
        package_bag.add(ctx.sender(), attestation);
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
    let attestation: &mut Attestation<T> = package_bag.borrow_mut(revoke_cap.created_by);

    // Modify attestation object
    attestation.revoked_by = option::some(ctx.sender());

    // Freeze revocation capability, since it can't be used again
    transfer::public_freeze_object(revoke_cap);
}

/// Pin attestation (using Publisher of the attestation.receiver)
public fun pin<T: key + store>(
    receiver_publisher: &mut Publisher,
    attestation_receiver: address,
    attestation_created_by: address,
    registry: &mut Registry
) {
    assert!(receiver_publisher.published_package() == attestation_receiver.to_ascii_string(), EInvalidReceiverPublisher);
    let package_bag = registry.attestations.borrow_mut(attestation_receiver);
    let attestation: &mut Attestation<T> = package_bag.borrow_mut(attestation_created_by);

    // Modify attestation object
    attestation.is_pinned = true;
}

// Unpin attestation (using Publisher of the attestation.receiver)
public fun unpin<T: key + store>(
    receiver_publisher: &mut Publisher,
    attestation_receiver: address,
    attestation_created_by: address,
    registry: &mut Registry
) {
    assert!(receiver_publisher.published_package() == attestation_receiver.to_ascii_string(), EInvalidReceiverPublisher);
    let package_bag = registry.attestations.borrow_mut(attestation_receiver);
    let attestation: &mut Attestation<T> = package_bag.borrow_mut(attestation_created_by);

    // Modify attestation object
    attestation.is_pinned = false;
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(ATTESTATION {}, ctx)
}
