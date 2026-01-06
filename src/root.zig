//! Compile-time bitfield generation for Zig.
//!
//! This library enables easy creation of bitfields for protocol headers, register
//! definitions, and other packed binary formats. Bitfields are defined using
//! schemas at compile time and provide type-safe access to individual fields.
//!
//! Example:
//!
//! ```zig
//! const Header = bitfield.BitField(.{
//!     .fields = &.{
//!         .Int("id", .{ .bits = 16 }),
//!         .Bool("flag", .{}),
//!     },
//! });
//! ```

const std = @import("std");
const validator = @import("validator.zig");

pub const Validator = validator.Validator;
pub const validators = validator.validators;

/// Schema defines the overall shape of a bitfield. Callers can define the order
/// and type of various fields that should be represented within the bitfield.
/// See the helper functions for field types as well as their associated options
/// for further details.
pub const Schema = struct {
    /// A list of fields that should be included in the bitfield produced by
    /// this schema. Note that the fields will be logically placed from "most
    /// significant" to "least significant." So, the first field will be at the
    /// top-most bit position(s) in the field. This differs from how Zig lays
    /// out packed structs, for instance, but is (hopefully) more intuitive
    /// as a layout.
    fields: []const Field,

    /// A component field within the bitfield. Several types are available,
    /// corresponding to common patterns seen within applications that rely
    /// on bitfields. You may construct these manually, if you'd like, but
    /// helper associated functions are available for a nicer development
    /// experience.
    pub const Field = struct {
        /// The name of the field. This is how the field will be labeled within
        /// the resulting packed struct.
        name: [:0]const u8,

        /// The data type of the field.
        type: type,

        /// An optional default value for the field in instances of the bitfield.
        /// This is primarily useful when creating instances using `fromData`,
        /// in which case users will not be required to enter a value for the
        /// field. It will have no bearing on instances created using `decode`,
        /// however, since the actual value will be extracted from input.
        default: ?*const anyopaque = null,

        /// An optional validation rule for the field.
        validator: ?Validator = null,

        /// Create a boolean field. Useful for on-off flags. Customization is
        /// available via `BoolOptions`.
        pub fn Bool(name: [:0]const u8, opts: BoolOptions) Field {
            return .{
                .name = name,
                .type = bool,
                .default = if (opts.default) |default| &default else null,
                .validator = opts.validator,
            };
        }

        /// BoolOptions allows customization of boolean fields.
        pub const BoolOptions = struct {
            /// When creating instances of the bitfield type, you may provide
            /// a default value. This reduces a bit of copying and pasting
            /// when producing new instances using the `fromData` function,
            /// particularly if there is a reasonable default or common value
            /// for the field. However, it has no impact when either encoding
            /// or decoding bitfields.
            default: ?bool = null,

            /// An optional validation rule for the field.
            validator: ?Validator = null,
        };

        /// Produce an enumerated field. Useful for sets of related bits, such
        /// as headers that indicate how to interpret a payload. Note that this
        /// also includes 1-bit fields that may be easier to reason about using
        /// named labels rather than simple booleans. Customization is available
        /// via `EnumOptions`. The provided `EnumOptions` must include the type
        /// of enum in it.
        pub fn Enum(name: [:0]const u8, opts: EnumOptions) Field {
            const type_info = @typeInfo(opts.type);
            if (type_info != .@"enum") {
                @compileError("provided type must be an enum");
            }

            return .{
                .name = name,
                .type = opts.type,
                .default = null,
                .validator = opts.validator,
            };
        }

        /// EnumOptions allows customization of enum fields. You must supply
        /// the enum type.
        pub const EnumOptions = struct {
            /// The type of the enum to include in the bitfield. Ideally,
            /// this type would have a declared size (for example, using enum(u4)),
            /// but even for enums without a specified size, the bitfield will
            /// support the size calculated based on the number of enum values.
            ///
            /// Note: Currently, this library does not provide special handling
            /// for undeclared values of exhaustive enums. If an enum has values
            /// corresponding to 0, 1, and 2, however a bitfield includes value
            /// 4, this won't trigger an error. However, if you attempt to use
            /// this in a switch statement without first checking validity,
            /// this is illegal behavior. So, be sure to check the value
            /// before using it. Alternatively, if your enum is non-exhaustive,
            /// then you will naturally handle this case with an `else` clause
            /// in the switch.
            type: type,

            /// An optional validation rule for the field.
            validator: ?Validator = null,
        };

        /// Padding inserts padding bits into the bitfield. This only supports
        /// static padding currently (think: reserved bits in protocol headers).
        /// Customization is available via `PaddingOptions`.
        pub fn Padding(name: [:0]const u8, opts: PaddingOptions) Field {
            const T = @Type(.{
                .int = .{
                    .signedness = .unsigned,
                    .bits = opts.bits,
                },
            });

            const val = if (opts.exact) validators.Exact.init(
                T,
                @as(T, opts.value),
                .{
                    .err = opts.err,
                },
            ) else null;

            return .{
                .name = name,
                .type = T,
                .default = &@as(T, opts.value),
                .validator = val,
            };
        }

        /// PaddingOptions enables customization of padding fields. You must
        /// supply the number of bits to pad. You may also optionally indicate
        /// the value to pad with. This defaults to 0 represented as an
        /// unsigned integer of size `bits`.
        pub const PaddingOptions = struct {
            /// The bit width of the padding. If you want 8 bits of padding, you
            /// would supply `8` as the value.
            bits: u16,

            /// The value with which to fill the padded space. This value
            /// is assumed to be part of the contract of the bitfield - attempts
            /// to encode or decode other values will produce validation errors.
            value: u16 = 0,

            /// Validate that padding bits exactly match the provided value.
            /// This is enabled by default.
            exact: bool = true,

            /// Set a custom error return value for mismatched padding bits.
            /// For example, if a 3-bit pad should equal 000, but it is actually
            /// 001, this error will be returned. By default, errors would
            /// be `error.InvalidFieldValue`. Note that validation will only
            /// happen when `exact` is true (which it is by default); if you
            /// set it to false, then there will be no validation performed that
            /// could produce this custom error.
            err: anyerror = error.InvalidFieldValue,
        };

        /// Create an integer field. Useful for protocol header fields that include
        /// numbers or counts. Customization is available via `IntOptions`.
        pub fn Int(name: [:0]const u8, opts: IntOptions) Field {
            const T = @Type(.{
                .int = .{
                    .signedness = opts.signedness,
                    .bits = opts.bits,
                },
            });

            const val: ?Validator = opts.validator orelse val_blk: {
                // Minimum is set
                if (opts.min) |min| {
                    // And so is maximum
                    if (opts.max) |max| {
                        break :val_blk validators.Range.init(
                            T,
                            @as(T, min),
                            @as(T, max),
                            .{
                                .min_err = opts.min_error,
                                .max_err = opts.max_error,
                            },
                        );
                    }

                    // Only minimum is set
                    break :val_blk validators.Min.init(T, @as(T, min), .{
                        .err = opts.min_error,
                    });
                }

                // Only maximum is set
                if (opts.max) |max| {
                    break :val_blk validators.Max.init(T, @as(T, max), .{
                        .err = opts.max_error,
                    });
                }

                // No validation is set
                break :val_blk null;
            };

            if (val) |v| {
                if (opts.default) |def| {
                    v.validate(def) catch @compileError("default value is invalid for provided validation rule");
                }
            }

            return .{
                .name = name,
                .type = T,
                .default = if (opts.default) |default| &default else null,
                .validator = val,
            };
        }

        /// IntOptions enables customization of integer fields. You must supply
        /// the number of bits for the type, however other fields are optional.
        pub const IntOptions = struct {
            /// The bit width of the integer. If you want an 8-bit number, you
            /// would supply `8` as the value.
            bits: u16,

            /// Configure whether this should be treated as an unsigned integer
            /// (the default) or a signed integer.
            signedness: std.builtin.Signedness = .unsigned,

            /// When creating instances of the bitfield type, you may provide
            /// a default value. This reduces a bit of copying and pasting
            /// when producing new instances using the `fromData` function,
            /// particularly if there is a reasonable default or common value
            /// for the field. However, it has no impact when either encoding
            /// or decoding bitfields.
            default: ?u16 = null,

            /// Minimum value for the integer field. If non-null, any
            /// encoding or decoding of the field will ensure that the actual
            /// value is at least as great as the provided value.
            min: ?comptime_int = null,

            /// The error to return when `min` has been set and validation fails.
            min_error: anyerror = error.ValueBelowMinimum,

            /// Maximum value for the integer field. If non-null, any encoding
            /// or decoding of the field will ensure that the actual value is
            /// no greater than the provided value.
            max: ?comptime_int = null,

            /// The error to return when `max` has been set and validation fails.
            max_error: anyerror = error.ValueAboveMaximum,

            /// An optional validation rule for the field. If this is not null,
            /// it will take precedence over any `min` or `max` provided in the
            /// options.
            validator: ?Validator = null,
        };
    };
};

/// Bitfield is a data type representing a packed, fixed-size set of elements,
/// which may be combined into a single numeric representation. Common uses
/// include protocol headers, register access, etc. The type will include a
/// backing field, whose values can be access directly by name, rather than
/// by using bitwise operations required of a native packed struct. Additionally,
/// validation capabilities are included on a per-field basis. Callers must
/// provide a schema for the bitfield.
pub fn BitField(comptime schema: Schema) type {
    if (schema.fields.len == 0) {
        @compileError("bitfield must have at least one field");
    }
    comptime var struct_fields: [schema.fields.len]std.builtin.Type.StructField = undefined;

    // Reverse the fields so that they get into the right order for Zig packed
    // structs.
    inline for (0..schema.fields.len) |i| {
        const field = schema.fields[i];
        const order = schema.fields.len - i - 1;
        struct_fields[order] = .{
            .name = field.name,
            .type = field.type,
            .is_comptime = false,
            .alignment = 0,
            .default_value_ptr = field.default,
        };
    }

    const Data = @Type(
        .{
            .@"struct" = .{
                .layout = .@"packed",
                .fields = &struct_fields,
                .is_tuple = false,
                .decls = &.{},
            },
        },
    );

    const T = @Type(
        .{
            .int = .{
                .signedness = .unsigned,
                .bits = @bitSizeOf(Data),
            },
        },
    );

    return struct {
        data: Data,

        const Self = @This();

        /// Produce a new bitfield from an underlying data structure. Validation
        /// failures will return errors, to avoid representing invalid states.
        pub fn fromData(data: Data) !Self {
            const self: Self = .{
                .data = data,
            };
            try self.validate();
            return self;
        }

        /// Decode a numeric input into a bitfield. This does not include any
        /// endianness considerations, which should, instead, be handled during
        /// deserialization. Validation failures will return errors, to avoid
        /// representing invalid states.
        pub fn decode(input: T) !Self {
            const self: Self = .{
                .data = @bitCast(input),
            };
            try self.validate();
            return self;
        }

        /// Encode a bitfield into its numeric representation. This does not
        /// include any endianness considerations, which should, instead,
        /// be handled during serialization. Validation failures will return
        /// errors, to avoid representing invalid states.
        pub fn encode(self: Self) !T {
            try self.validate();
            return @bitCast(self.data);
        }

        /// Validate the contents of the bitfield. For each sub-field that was
        /// defined with a validator, execute that validator.
        pub fn validate(self: Self) !void {
            inline for (schema.fields) |field| {
                if (field.validator) |field_validator| {
                    const value = @field(self.data, field.name);
                    try field_validator.validate(value);
                }
            }
        }

        /// Print a representation of the bitfield to the provided writer,
        /// useful for debugging. It shows the field names and values within
        /// a bitfield struct, with newlines in between.
        pub fn format(self: Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.print("bitfield: {{\n", .{});
            const fields = std.meta.fields(Data);
            inline for (0..fields.len) |i| {
                // Iterate over the fields in most-significant to least-significant
                // order, similar to how fields are defined in schemas.
                const j = fields.len - i - 1;
                try w.print(" .{s} = ", .{fields[j].name});
                try w.print("{any},\n", .{@field(self.data, fields[j].name)});
            }
            try w.print("}}", .{});
        }
    };
}

test {
    std.testing.refAllDecls(@This());
}
