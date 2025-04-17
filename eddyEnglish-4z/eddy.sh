#!/bin/bash

# ====================================================
# Script Name: setup_printer_config.sh
# Function:
#   1. Check if ~/printer_data/config/eddypz.cfg exists, delete it if it does,
#      then recreate it and add configuration content.
#   2. Add "[include eddypz.cfg] #eddy_config" to the first line of ~/printer_data/config/printer.cfg
#      if it doesn't already exist.

# ====================================================


# Set target file paths
PRINTER_CFG="$HOME/printer_data/config/printer.cfg"
EDDPZ_CFG="$HOME/printer_data/config/eddypz.cfg"
FILE="$HOME/klipper/klippy/extras/ldc1612.py"

# Define content to add to printer.cfg
PRINTER_CFG_CONTENT="[include eddypz.cfg]"
PRINTER_CFG_CONTEN="[probe_eddy_current fly_eddy_probe]\nz_offset: 1.0"

# Define content to add to eddypz.cfg, separated for processing
PROBE_EDDY_CURRENT=$(cat <<EOF
[probe_eddy_current fly_eddy_probe]
sensor_type: ldc1612
#frequency: 40000000 # Frequency set to 40MHz
i2c_address: 43
i2c_mcu: SHT36
i2c_bus: i2c1e
x_offset: 0 # Remember to set x offset
y_offset: 0 # Remember to set y offset 
speed:10
lift_speed: 15.0
i2c_speed: 4000000
EOF
)

TEMPERATURE_PROBE=$(cat <<EOF
[temperature_probe fly_eddy_probe]
sensor_type: Generic 3950
sensor_pin:SHT36:gpio28
EOF
)

FORCE_MOVE=$(cat <<EOF
[force_move]
enable_force_move: true
EOF
)

GCODE_MACRO_CALIBRATE_EDDY=$(cat <<EOF
[gcode_macro CALIBRATE_EDDY]
description: Execute Eddy Current Sensor Calibration and Subsequent Leveling Process
gcode:
    # ========== Start Calibrating Eddy Current Sensor ==========
    M117 Starting Eddy Current Sensor Calibration...

    # Safety Check: Verify if the printer is in pause state
    {% if printer.pause_resume.is_paused|lower == 'true' %}
        {action_raise_error("Please resume printing before calibration")}
    {% endif %}
    G28 X Y
    G0 X{printer.toolhead.axis_maximum.x / 2} Y{printer.toolhead.axis_maximum.y / 2} F6000
    SET_KINEMATIC_POSITION Z=0

    # Execute Calibration Process 
    LDC_CALIBRATE_DRIVE_CURRENT CHIP=fly_eddy_probe 

    # Attempt to output DRIVE_CURRENT_FEEDBACK value
    M117 Eddy Current Calibration Complete, Feedback Value: {DRIVE_CURRENT_FEEDBACK}

    # Check if Feedback Value is within Normal Range
    {% if DRIVE_CURRENT_FEEDBACK is defined %}
        {% if DRIVE_CURRENT_FEEDBACK < 10 or DRIVE_CURRENT_FEEDBACK > 20 %}
            M117 Warning: Eddy Current Feedback Value Abnormal ({DRIVE_CURRENT_FEEDBACK}). Please check connections.
        {% else %}
            M117 Eddy Current Feedback Value Normal ({DRIVE_CURRENT_FEEDBACK}).
        {% endif %}
    {% else %}
        M117 Error: Unable to retrieve DRIVE_CURRENT_FEEDBACK value.
    {% endif %}
    
    G1 Z15 F300
    
    # Prompt user to perform manual Z Offset Calibration
    M117 Please perform manual Z Offset Calibration.
    SET_KINEMATIC_POSITION Z={printer.toolhead.axis_maximum.z-10}
    # Execute Eddy Effective Distance Calibration
    PROBE_EDDY_CURRENT_CALIBRATE CHIP=fly_eddy_probe 

    # Indicate Calibration Completion
    M117 All Calibration Processes Completed!
EOF
)

GCODE_MACRO_TEMP_COMPENSATION=$(cat <<EOF
[gcode_macro TEMP_COMPENSATION]
description: Temperature Compensation Calibration Process
gcode:
  {% set bed_temp = params.BED_TEMP|default(90)|int %}
  {% set nozzle_temp = params.NOZZLE_TEMP|default(250)|int %}
  {% set temperature_range_value = params.TEMPERATURE_RANGE_VALUE|default(3)|int %}
  {% set desired_temperature = params.DESIRED_TEMPERATURE|default(80)|int %}
  {% set Temperature_Timeout_Duration = params.TEMPERATURE_TIMEOUT_DURATION|default(6500000000)|int %}
    # Safety check: Ensure all axes are unlocked
    {% if printer.pause_resume.is_paused %}
        { action_raise_error("Error: Printer is paused. Please resume first.") }
    {% endif %}
    # Step 1: Home all axes
    STATUS_MESSAGE="Homing all axes..."
    G28
    STATUS_MESSAGE="Homing completed"
    # Step 2: Auto-leveling
    QUAD_GANTRY_LEVEL
    # Step 3: Safely raise the Z-axis
    STATUS_MESSAGE="Raising Z-axis..."
    G90
    G0 Z5 F2000  # Raise slowly to prevent collisions
    # Step 4: Set timeout and temperature calibration
    SET_IDLE_TIMEOUT TIMEOUT={Temperature_Timeout_Duration}
    STATUS_MESSAGE="Starting temperature probe calibration..."
    TEMPERATURE_PROBE_CALIBRATE PROBE=fly_eddy_probe TARGET={desired_temperature} STEP={temperature_range_value}
    # Step 5: Set printing temperatures (modify as needed)
    STATUS_MESSAGE="Setting working temperatures..."
    SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET={bed_temp}
    SET_HEATER_TEMPERATURE HEATER=extruder TARGET={nozzle_temp}
    # Completion message
    STATUS_MESSAGE="Temperature compensation process completed!"
    description: G-Code macro
EOF
)

GCODE_MACRO_CANCEL_TEMP_COMPENSATION=$(cat <<EOF
[gcode_macro CANCEL_TEMP_COMPENSATION]
description: Abort Temperature Compensation Process
gcode:
    SET_IDLE_TIMEOUT TIMEOUT=600  # Restore default timeout
    TURN_OFF_HEATERS
    M117 Calibration aborted
EOF
)

GCODE_MACRO_BED_MESH_CALIBRATE=$(cat <<EOF
[gcode_macro BED_MESH_CALIBRATE]
rename_existing: _BED_MESH_CALIBRATE
gcode: 
       _BED_MESH_CALIBRATE horizontal_move_z=2 METHOD=rapid_scan {rawparams}
       G28 X Y
EOF
)


GCODE_MACRO_QUAD_GANTRY_LEVEL=$(cat <<EOF
[gcode_macro QUAD_GANTRY_LEVEL]
rename_existing: _QUAD_GANTRY_LEVEL 
gcode:
    # ========== State Save ==========
    SAVE_GCODE_STATE NAME=STATE_QGL 
    
    # ========== Environment Preparation ==========
    BED_MESH_CLEAR                       # Clear existing bed mesh data 
    
    # ========== Main Leveling Process ==========
    {% if not printer.quad_gantry_level.applied %}
        # Initial coarse adjustment 
        _QUAD_GANTRY_LEVEL horizontal_move_z=10 retry_tolerance=1
        G0 Z10 F6000                     # Use standard G-code commands instead of HORIZONTAL_MOVE_Z
        # Set retry tolerance and speed
        # Note: Specific parameters depend on _QUAD_GANTRY_LEVEL macro implementation
        # For example, if _QUAD_GANTRY_LEVEL supports RETRY_TOLERANCE parameter:
        # _QUAD_GANTRY_LEVEL RETRY_TOLERANCE=0.1 SPEED=200.0
    {% endif %}
    
    # Fine secondary leveling 
     _QUAD_GANTRY_LEVEL horizontal_move_z=2 retry_tolerance=0.005 retries=20 METHOD=rapid_scan ADAPTIVE=1
        G0 Z10 F6000                     # Use standard G-code commands instead of HORIZONTAL_MOVE_Z
        # Set auto-compensation algorithm, maximum adjustments, and speed
        # Note: RETRY_TOLERANCE may have been set previously or adjusted as needed
    
    # ========== Post-Processing ==========
    G90                                 # Force absolute coordinate mode 
    G0 Z10 F6000                        # Raise Z axis to safe height 
    M117 QGL Completed                  # Display completion status 
    G28                                 # Return to origin
    # ========== State Restore ==========
    RESTORE_GCODE_STATE NAME=STATE_QGL 
    M400                
EOF
)

GCODE_MACRO_CALIBRATE_DD=$(cat <<EOF
[gcode_macro CALIBRATE_DD]
description: Mobile axis macro
gcode:
    # Reset X/Y Axis 
    G28 X Y 

    # Move the print head to the center of the heated bed (compatible with most CoreXY models)
    G0 X{printer.toolhead.axis_maximum.x / 2} Y{printer.toolhead.axis_maximum.y / 2} F6000 
    SET_KINEMATIC_POSITION Z={printer.toolhead.axis_maximum.z-10}
EOF
)


SAVE_VARIABLES=$(cat <<EOF
[save_variables]
filename: ~/printer_data/config/variables.cfg
EOF
)

DELAYED_GCODE_RESTORE_PROBE_OFFSET=$(cat <<EOF
[delayed_gcode RESTORE_PROBE_OFFSET]
initial_duration: 1.
gcode:
  {% set svv = printer.save_variables.variables %}
  {% if not printer["gcode_macro SET_GCODE_OFFSET"].restored %}
    SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=runtime_offset VALUE={ svv.nvm_offset|default(0) }
    SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=restored VALUE=True
  {% endif %}
EOF
)

GCODE_MACRO_G28=$(cat <<EOF
[gcode_macro G28]
rename_existing: G28.1
gcode:
  G28.1 {rawparams}
  {% if not rawparams or (rawparams and 'Z' in rawparams) %}
    PROBE
    SET_Z_FROM_PROBE
  {% endif %}
EOF
)

GCODE_MACRO_SET_Z_FROM_PROBE=$(cat <<EOF
[gcode_macro SET_Z_FROM_PROBE]
gcode:
    {% set cf = printer.configfile.settings %}
    SET_GCODE_OFFSET_ORIG Z={printer.probe.last_z_result - cf['probe_eddy_current fly_eddy_probe'].z_offset + printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset}
    G90
    G1 Z{cf.safe_z_home.z_hop}
EOF
)

GCODE_MACRO_SET_Z_FROM_PROBE=$(cat <<EOF
[gcode_macro Z_OFFSET_APPLY_PROBE]
rename_existing: Z_OFFSET_APPLY_PROBE_ORIG
gcode:
  SAVE_VARIABLE VARIABLE=nvm_offset VALUE={ printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset }
EOF
)

# ================================
# Function 1: Check if eddypz.cfg exists, delete it if it does,
#            then recreate it and add configuration content.
# ================================

echo "Checking for eddypz.cfg file..."

if [ -f "$EDDPZ_CFG" ]; then
    echo "File exists: $EDDPZ_CFG"
    read -p "Do you want to delete the existing eddypz.cfg file and recreate it? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm "$EDDPZ_CFG"
        echo "Deleted file: $EDDPZ_CFG"
    else
        echo "Operation cancelled. Script terminated."
        exit 0
    fi
fi

# Create new eddypz.cfg and add configuration content
touch "$EDDPZ_CFG"
add_config() {
    local config_name=$1
    local config_content=$2

    echo "Processing config block: $config_name"
    IFS=$'\n' read -r -d '' -a LINES <<< "$config_content"

    for LINE in "${LINES[@]}"; do
        # Strip leading and trailing whitespace and escape special characters
        LINE_CLEAN=$(echo "$LINE" | sed 's/[][\.^$*]/\\&/g' | xargs)
        
        # Use grep to check if the entire line exists (ignoring leading/trailing whitespace)
        if ! grep -Fxq "^${LINE_CLEAN}$" "$EDDPZ_CFG"; then
            echo "$LINE" >> "$EDDPZ_CFG"
            echo "Added: $LINE"
        else
            echo "Already exists, skipping: $LINE"
        fi
    done

    # Add an empty line after each config block if not already present
    if ! grep -qxE '' "$EDDPZ_CFG"; then
        echo "" >> "$EDDPZ_CFG"
        echo "Added empty line"
    fi
}

# Add each configuration block
add_config "probe_eddy_current" "$PROBE_EDDY_CURRENT"
add_config "temperature_probe" "$TEMPERATURE_PROBE"
add_config "gcode_macro_CALIBRATE_EDDY" "$GCODE_MACRO_CALIBRATE_EDDY"
add_config "gcode_macro_TEMP_COMPENSATION" "$GCODE_MACRO_TEMP_COMPENSATION"
add_config "gcode_macro_CANCEL_TEMP_COMPENSATION" "$GCODE_MACRO_CANCEL_TEMP_COMPENSATION"
add_config "gcode_macro_BED_MESH_CALIBRATE" "$GCODE_MACRO_BED_MESH_CALIBRATE"
add_config "gcode_macro_QUAD_GANTRY_LEVEL" "$GCODE_MACRO_QUAD_GANTRY_LEVEL"
add_config "force_move" "$FORCE_MOVE"
add_config "gcode_macro_CALIBRATE_DD" "$GCODE_MACRO_CALIBRATE_DD"
add_config "save_variables" "$SAVE_VARIABLES"
add_config "delayed_gcode RESTORE_PROBE_OFFSET" "$DELAYED_GCODE_RESTORE_PROBE_OFFSET"
add_config "gcode_macro_G28" "$GCODE_MACRO_G28"
add_config "gcode_macro_SET_Z_FROM_PROBE" "$GCODE_MACRO_SET_Z_FROM_PROBE"
add_config "gcode_macro_Z_OFFSET_APPLY_PROBE" "$GCODE_MACRO_SET_Z_FROM_PROBE"
echo "eddypz.cfg file has been updated."

# ================================
# Function 2: Add "[include eddypz.cfg] #eddy_config" to the first line of printer.cfg
#            if it doesn't already exist.
# ================================
# Check if printer.cfg exists
if [ ! -f "$PRINTER_CFG" ]; then
    echo "Target file does not exist: $PRINTER_CFG"
    touch "$PRINTER_CFG"
    echo "Created new file: $PRINTER_CFG"
fi

# Normalize line endings to prevent mismatches due to Windows line endings
sed -i 's/\r$//' "$PRINTER_CFG"

# Define search pattern to allow whitespace around and ignore case
SEARCH_PATTERN='^\s*$$include\s*eddypz\.cfg$$\s*#\s*eddy\s*configuration\s*$'
SEARCH_PATTER='^\s*$$probe_eddy_current\s+fly_eddy_probe$$\s*$'

# Check if "[include eddypz.cfg] #eddy configuration" already exists
if grep -Eiq "$SEARCH_PATTERN" "$PRINTER_CFG"; then
    echo "[include eddypz.cfg] #eddy configuration already exists in $PRINTER_CFG, skipping addition."
else
    # Insert the new line at the beginning of the file
    sed -i "1i$PRINTER_CFG_CONTENT" "$PRINTER_CFG"
    echo "Added '[include eddypz.cfg] #eddy configuration' to the first line of $PRINTER_CFG"
fi

if grep -Eiq "$SEARCH_PATTER" "$PRINTER_CFG"; then
    echo "[probe_eddy_current fly_eddy_probe] already exists in $PRINTER_CFG, skipping addition."
else
    # Insert a new line at the beginning of the file.
    sed -i "2i$PRINTER_CFG_CONTEN" "$PRINTER_CFG"
    echo "Already added [probe_eddy_current fly_eddy_probe] to... $PRINTER_CFG "
fi

echo "All operations completed."
echo "Restarting Klipper service..."

# Restart Klipper service
sudo systemctl restart klipper

# Check if restart was successful
if systemctl is-active --quiet klipper; then
    echo "Klipper service restarted successfully."
else
    echo "Failed to restart Klipper service. Please check logs for more information."
    exit 1
fi

# Error handling function: Output error message and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check if FILE exists
if [ ! -f "$FILE" ]; then
    error_exit "File '$FILE' does not exist."
fi

# Check if FILE is writable
if [ ! -w "$FILE" ]; then
    error_exit "File '$FILE' is not writable. Please check permissions."
fi

# Backup original file
cp "$FILE" "${FILE}.bak" || error_exit "Failed to backup file '$FILE'."

# Perform replacement operation
sed -i 's/LDC1612_FREQ = 12000000/LDC1612_FREQ = 40000000/g' "$FILE" || error_exit "Replacement operation failed."

# Check if the replacement was successful
if grep -q "^LDC1612_FREQ = 40000000$" "$FILE"; then
    echo "Replacement successful: 'LDC1612_FREQ = 40000000' found."
else
    echo "Warning: 'LDC1612_FREQ = 40000000' not found." >&2
fi
