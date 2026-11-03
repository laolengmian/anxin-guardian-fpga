`timescale 1ns/1ps

// Exact runtime whitelist for BMP input geometry. The selected profile only
// describes source/scaler geometry; frame-bank ownership remains in the loader.
module m9_bmp_profile_decoder #(
    parameter integer PROFILE0_WIDTH=640,
    parameter integer PROFILE0_HEIGHT=480,
    parameter integer PROFILE0_SCALED_WIDTH=960,
    parameter integer PROFILE0_SCALED_HEIGHT=720,
    parameter integer PROFILE0_X_OFFSET=160,
    parameter integer PROFILE1_WIDTH=800,
    parameter integer PROFILE1_HEIGHT=600,
    parameter integer PROFILE1_SCALED_WIDTH=960,
    parameter integer PROFILE1_SCALED_HEIGHT=720,
    parameter integer PROFILE1_X_OFFSET=160,
    parameter integer PROFILE2_WIDTH=1024,
    parameter integer PROFILE2_HEIGHT=576,
    parameter integer PROFILE2_SCALED_WIDTH=1280,
    parameter integer PROFILE2_SCALED_HEIGHT=720,
    parameter integer PROFILE2_X_OFFSET=0,
    parameter integer PROFILE3_WIDTH=1280,
    parameter integer PROFILE3_HEIGHT=720,
    parameter integer PROFILE3_SCALED_WIDTH=1280,
    parameter integer PROFILE3_SCALED_HEIGHT=720,
    parameter integer PROFILE3_X_OFFSET=0
) (
    input wire [31:0] image_width,
    input wire [31:0] image_height,
    output reg profile_valid,
    output reg [1:0] profile_id,
    output reg [10:0] source_width,
    output reg [9:0] source_height,
    output reg [10:0] scaled_width,
    output reg [9:0] scaled_height,
    output reg [10:0] x_offset,
    output reg [9:0] y_offset,
    output reg [2:0] scale_numerator,
    output reg [2:0] scale_denominator,
    output reg [12:0] source_row_bytes,
    output reg [12:0] source_row_stride,
    output reg [31:0] source_data_bytes
);
    localparam integer P0_ROW_BYTES=PROFILE0_WIDTH*3;
    localparam integer P0_ROW_STRIDE=((P0_ROW_BYTES+3)/4)*4;
    localparam integer P1_ROW_BYTES=PROFILE1_WIDTH*3;
    localparam integer P1_ROW_STRIDE=((P1_ROW_BYTES+3)/4)*4;
    localparam integer P2_ROW_BYTES=PROFILE2_WIDTH*3;
    localparam integer P2_ROW_STRIDE=((P2_ROW_BYTES+3)/4)*4;
    localparam integer P3_ROW_BYTES=PROFILE3_WIDTH*3;
    localparam integer P3_ROW_STRIDE=((P3_ROW_BYTES+3)/4)*4;

    task select_profile;
        input [1:0] id;
        input integer width;
        input integer height;
        input integer output_width;
        input integer output_height;
        input integer offset;
        input [2:0] numerator;
        input [2:0] denominator;
        input integer row_bytes;
        input integer row_stride;
        begin
            profile_valid=1'b1;
            profile_id=id;
            source_width=width[10:0];
            source_height=height[9:0];
            scaled_width=output_width[10:0];
            scaled_height=output_height[9:0];
            x_offset=offset[10:0];
            y_offset=10'd0;
            scale_numerator=numerator;
            scale_denominator=denominator;
            source_row_bytes=row_bytes[12:0];
            source_row_stride=row_stride[12:0];
            source_data_bytes=row_stride*height;
        end
    endtask

    always @* begin
        profile_valid=1'b0;
        profile_id=2'd0;
        source_width=11'd0;
        source_height=10'd0;
        scaled_width=11'd0;
        scaled_height=10'd0;
        x_offset=11'd0;
        y_offset=10'd0;
        scale_numerator=3'd0;
        scale_denominator=3'd0;
        source_row_bytes=13'd0;
        source_row_stride=13'd0;
        source_data_bytes=32'd0;
        if(image_width==PROFILE0_WIDTH && image_height==PROFILE0_HEIGHT)
            select_profile(2'd0,PROFILE0_WIDTH,PROFILE0_HEIGHT,
                           PROFILE0_SCALED_WIDTH,PROFILE0_SCALED_HEIGHT,
                           PROFILE0_X_OFFSET,3'd3,3'd2,
                           P0_ROW_BYTES,P0_ROW_STRIDE);
        else if(image_width==PROFILE1_WIDTH && image_height==PROFILE1_HEIGHT)
            select_profile(2'd1,PROFILE1_WIDTH,PROFILE1_HEIGHT,
                           PROFILE1_SCALED_WIDTH,PROFILE1_SCALED_HEIGHT,
                           PROFILE1_X_OFFSET,3'd6,3'd5,
                           P1_ROW_BYTES,P1_ROW_STRIDE);
        else if(image_width==PROFILE2_WIDTH && image_height==PROFILE2_HEIGHT)
            select_profile(2'd2,PROFILE2_WIDTH,PROFILE2_HEIGHT,
                           PROFILE2_SCALED_WIDTH,PROFILE2_SCALED_HEIGHT,
                           PROFILE2_X_OFFSET,3'd5,3'd4,
                           P2_ROW_BYTES,P2_ROW_STRIDE);
        else if(image_width==PROFILE3_WIDTH && image_height==PROFILE3_HEIGHT)
            select_profile(2'd3,PROFILE3_WIDTH,PROFILE3_HEIGHT,
                           PROFILE3_SCALED_WIDTH,PROFILE3_SCALED_HEIGHT,
                           PROFILE3_X_OFFSET,3'd1,3'd1,
                           P3_ROW_BYTES,P3_ROW_STRIDE);
    end
endmodule
