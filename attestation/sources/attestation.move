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
    attested: Table<address /* receiver */, Bag /* attestation_id, Attestation<T> */>,
    pinned: Table<address /* receiver */, Bag /* attestation_id, Attestation<T> */>,
    revoked: Table<address /* receiver */, Bag /* attestation_id, Attestation<T> */>,
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
    was_pinned: bool,
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
        attested: table::new(ctx),
        pinned: table::new(ctx),
        revoked: table::new(ctx),
    };

    transfer::share_object(registry);
}

/// Register attestation type and its Display
#[allow(lint(freeze_wrapped))]
public fun register_type<T: key + store>(
    registry: &mut Registry,
    type_publisher: Publisher,
    fields: vector<std::string::String>,
    values: vector<std::string::String>,
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
    registry: &mut Registry,
    _: &AttestationType<T>,
    data: T,
    receiver: address,
    ctx: &mut TxContext,
): RevokeCap {
    // Create attestation
    let attestation = Attestation {
        id: object::new(ctx),
        receiver,
        data,
        created_by: ctx.sender(),
        revoked_by: option::none(),
        was_pinned: false,
    };
    let attestation_id = object::id(&attestation);

    // Create revocation capability
    let revoke_cap = RevokeCap {
        id: object::new(ctx),
        receiver,
        attestation_id,
    };

    // Store attestation in the registry
    if (!registry.attested.contains(receiver)) {
        // if it's the first attestation for this package, create a new bag
        let mut attested_bag = bag::new(ctx);
        attested_bag.add(attestation_id, attestation);
        registry.attested.add(receiver, attested_bag);

        // also directly create empty bags for pinned and revoked attestations
        registry.pinned.add(receiver, bag::new(ctx));
        registry.revoked.add(receiver, bag::new(ctx));
    } else {
        // else, borrow existing bag
        let attested_bag = registry.attested.borrow_mut(receiver);
        attested_bag.add(attestation_id, attestation);
    };

    // Return revocation capability
    revoke_cap
}

/// Revoke attestation (using RevokeCap)
public fun revoke<T: key + store>(
    registry: &mut Registry,
    revoke_cap: RevokeCap,
    ctx: &mut TxContext,
) {
    // Get attestation from either attested or pinned bags
    let mut attestation: Attestation<T>;
    let attested_bag = registry.attested.borrow_mut(revoke_cap.receiver);
    if (attested_bag.contains(revoke_cap.attestation_id)) {
        attestation = attested_bag.remove(revoke_cap.attestation_id);
    } else {
        let pinned_bag = registry.pinned.borrow_mut(revoke_cap.receiver);
        attestation = pinned_bag.remove(revoke_cap.attestation_id);
    };

    // Modify attestation
    attestation.revoked_by = option::some(ctx.sender());

    // Move attestation to revoked bag
    let revoked_bag = registry.revoked.borrow_mut(revoke_cap.receiver);
    revoked_bag.add(object::id(&attestation), attestation);

    // Delete revocation capability, since it can't be used again
    let RevokeCap {
        id,
        receiver: _,
        attestation_id: _,
    } = revoke_cap;
    object::delete(id);
}

/// Pin attestation (using Publisher of the attestation.receiver)
public fun pin<T: key + store>(
    registry: &mut Registry,
    receiver_publisher: &mut Publisher,
    attestation_receiver: address,
    attestation_id: ID,
) {
    assert!(receiver_publisher.published_package() == attestation_receiver.to_ascii_string(), EInvalidReceiverPublisher);

    // Get attestation from attested bag (ignore revoked)
    let attested_bag = registry.attested.borrow_mut(attestation_receiver);
    let mut attestation: Attestation<T> = attested_bag.remove(attestation_id);

    // Modify before moving
    attestation.was_pinned = true;

    // Move attestation to pinned bag
    let pinned_bag = registry.pinned.borrow_mut(attestation_receiver);
    pinned_bag.add(object::id(&attestation), attestation);
}

/// Unpin attestation (using Publisher of the attestation.receiver)
public fun unpin<T: key + store>(
    registry: &mut Registry,
    receiver_publisher: &mut Publisher,
    attestation_receiver: address,
    attestation_id: ID,
) {
    assert!(receiver_publisher.published_package() == attestation_receiver.to_ascii_string(), EInvalidReceiverPublisher);

    // Get attestation from pinned bag (ignore revoked)
    let pinned_bag = registry.pinned.borrow_mut(attestation_receiver);
    let attestation: Attestation<T> = pinned_bag.remove(attestation_id);

    // Move attestation to attested bag
    let attested_bag = registry.attested.borrow_mut(attestation_receiver);
    attested_bag.add(attestation_id, attestation);
}

/// Return attestation for the given receiver
public fun attestation<T: key + store>(
    registry: &Registry,
    receiver: address,
    attestation_id: ID,
): &Attestation<T> {
    if (
        registry.attested.borrow(receiver).contains(attestation_id)
    ) {
        registry.attested.borrow(receiver).borrow(attestation_id)
    } else if (
        registry.revoked.borrow(receiver).contains(attestation_id)
    ) {
        registry.revoked.borrow(receiver).borrow(attestation_id)
    } else {
        registry.pinned.borrow(receiver).borrow(attestation_id)
    }
}

/// Return attestation.revoked_by field
public fun attestation_revoked_by<T: key + store>(
    registry: &Registry,
    receiver: address,
    attestation_id: ID,
): Option<address> {
    let attestation = registry.attestation<T>(receiver, attestation_id);
    attestation.revoked_by
}

/// Return attestation.was_pinned field
public fun attestation_was_pinned<T: key + store>(
    registry: &Registry,
    receiver: address,
    attestation_id: ID,
): bool {
    let attestation = registry.attestation<T>(receiver, attestation_id);
    attestation.was_pinned
}

/// Return revoke_cap.attestation_id field
public fun revoke_cap_attestation_id(
    revoke_cap: &RevokeCap,
): ID {
    revoke_cap.attestation_id
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(ATTESTATION {}, ctx)
}
