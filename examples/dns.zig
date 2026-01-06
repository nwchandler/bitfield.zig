//! This file contains an example bitfield usage for representing the
//! DNS message header. The format is demonstrated below (from RFC 1035):
//!
//!                                 1  1  1  1  1  1
//!   0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
//! +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
//! |                      ID                       |
//! +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
//! |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE   |
//! +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
//! |                    QDCOUNT                    |
//! +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
//! |                    ANCOUNT                    |
//! +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
//! |                    NSCOUNT                    |
//! +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
//! |                    ARCOUNT                    |
//! +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
//!
//! Octets 3 and 4 are made of flags, enums, and padding, while the other
//! octets can be interpreted directly as 16-bit unsigned integers.

const std = @import("std");
const bitfield = @import("bitfield");

/// This type demonstrates the definition of a DNS Header as a single bitfield.
/// Note that an actual DNS packet will also generally include further fields,
/// as described by the "count" fields. Application logic would need to decide
/// how to interpret the remainder of the packet, but this bitfield provides
/// a uniform way to gather the details required to support that further
/// interpretation.
const DnsHeader = bitfield.BitField(.{
    .fields = &.{
        .Int("id", .{ .bits = 16 }),
        .Enum("qr", .{ .type = qr }),
        .Enum("opcode", .{ .type = opcode }),
        .Bool("aa", .{}),
        .Bool("tc", .{ .default = false }),
        .Bool("rd", .{ .default = false }),
        .Bool("ra", .{ .default = false }),
        .Padding("z", .{ .bits = 3 }),
        .Enum("rcode", .{ .type = rcode }),
        .Int("qdcount", .{ .bits = 16, .default = 0 }),
        .Int("ancount", .{ .bits = 16, .default = 0 }),
        .Int("nscount", .{ .bits = 16, .default = 0 }),
        .Int("arcount", .{ .bits = 16, .default = 0 }),
    },
});

/// Single-bit enums can be useful in place of boolean fields when the meaning
/// of the bit may not be immediately evident. Here, the "qr" bit indicates
/// whether the message is a query (e.g., from a client to a server) or a
/// response (e.g., from a server to a client).
const qr = enum(u1) {
    query,
    response,
};

const opcode = enum(u4) {
    query = 0,
    iquery = 1,
    status = 2,
};

const rcode = enum(u4) {
    no_error = 0,
    format_error = 1,
    server_failure = 2,
    name_error = 3,
    not_implemented = 4,
    refused = 5,
};

pub fn main() !void {
    const request = try DnsHeader.fromData(.{
        .id = 1234,
        .qr = .query,
        .opcode = .query,
        .aa = false,
        .rcode = .no_error,
    });
    const encoded_request = try request.encode();
    std.debug.assert(encoded_request == 0x04D2_0000_0000_0000_0000_0000);

    //                                      id               flags            qdcount          ancount          nscount          arcount
    const parsed: DnsHeader = try .decode(0b0000000110011000_1000010000000000_0000000000000000_0000000000001111_0000000000000000_0000000000000000);
    std.debug.print("parsed: {f}\n", .{parsed});
}
