#!/bin/bash

# ====================================================
# 脚本名称: setup_printer_config.sh
# 功能:
#   1. 检查并删除 ~/printer_data/config/eddypz.cfg（如果存在），然后重新创建并添加配置内容。
#   2. 在 ~/printer_data/config/printer.cfg 文件的第一行添加 [include eddypz.cfg] #eddy配置（如果尚未存在）。
#   3. 删除 ~/printer_data/config/printer.cfg 中 [bed_mesh] 段落的 horizontal_move_z 值为 2 的内容。
# 使用方法:
#   ./setup_printer_config.sh
# ====================================================


# 设置目标文件路径
PRINTER_CFG="$HOME/printer_data/config/printer.cfg"
EDDPZ_CFG="$HOME/printer_data/config/eddypz.cfg"
FILE="$HOME/klipper/klippy/extras/ldc1612.py"

# 定义要添加到 printer.cfg 的内容
PRINTER_CFG_CONTENT="[include eddypz.cfg]"
PRINTER_CFG_CONTEN="[probe_eddy_current fly_eddy_probe]\nz_offset: 1.0"

# 定义要添加到 eddypz.cfg 的内容，分开处理
PROBE_EDDY_CURRENT=$(cat <<EOF
[probe_eddy_current fly_eddy_probe]
sensor_type: ldc1612
#frequency: 40000000 # 频率设置为 40MHz
i2c_address: 43
i2c_mcu: sb2040
i2c_bus: i2c1b
x_offset: 0 #记得设置x偏移
y_offset: 18 #记得设置y偏移 
speed:10
lift_speed: 15.0
i2c_speed: 4000000
EOF
)

TEMPERATURE_PROBE=$(cat <<EOF
[temperature_probe fly_eddy_probe]
sensor_type: NTC 100K MGB18-104F39050L32
sensor_pin: sb2040:gpio28
EOF
)

FORCE_MOVE=$(cat <<EOF
[force_move]
enable_force_move: true
EOF
)

GCODE_MACRO_CALIBRATE_DD=$(cat <<EOF
[gcode_macro CALIBRATE_DD]
description: 移动轴宏 
gcode:
    # 归零X/Y轴 
    G28 X Y

    # 移动打印头到热床中心（适配多数CoreXY机型）
    G0 X{printer.toolhead.axis_maximum.x / 2} Y{printer.toolhead.axis_maximum.y / 2} F6000 
    SET_KINEMATIC_POSITION Z=10
EOF
)

GCODE_MACRO_CALIBRATE_EDDY=$(cat <<EOF
[gcode_macro CALIBRATE_EDDY]
description: 执行Eddy电流传感器校准及后续调平流程 
gcode:
    # ========== LED灯效  ==========
    _status_calibrating_z

    # ========== 开始校准 Eddy 电流传感器 ==========
    RESPOND TYPE=command MSG="开始校准 Eddy 电流传感器..."

    # 安全检测：检查打印机是否处于暂停状态
    {% if printer.pause_resume.is_paused|lower == 'true' %}
        {action_raise_error("校准前请先恢复打印状态")}
    {% endif %}
    # M84
    {% if "xyz" not in printer.toolhead.homed_axes %}  
        G28 X Y 
        G0 X{printer.toolhead.axis_maximum.x / 2} Y{printer.toolhead.axis_maximum.y / 2} F6000
    {% endif %}
    SET_KINEMATIC_POSITION Z=0

    # 执行校准流程 
    G1 Z20 F3000
    LDC_CALIBRATE_DRIVE_CURRENT CHIP=fly_eddy_probe 

    # 尝试输出 DRIVE_CURRENT_FEEDBACK 的值
    RESPOND TYPE=command MSG="Eddy 电流校准完成，反馈值: {DRIVE_CURRENT_FEEDBACK}"

    # 检查反馈值是否在正常范围内
    {% if DRIVE_CURRENT_FEEDBACK is defined %}
        {% if DRIVE_CURRENT_FEEDBACK < 10 or DRIVE_CURRENT_FEEDBACK > 20 %}
            RESPOND TYPE=command MSG="警告:Eddy 电流反馈值异常({DRIVE_CURRENT_FEEDBACK})请检查连接"
        {% else %}
            RESPOND TYPE=command MSG="Eddy 电流反馈值正常({DRIVE_CURRENT_FEEDBACK})"
        {% endif %}
    {% else %}
        RESPOND TYPE=command MSG="错误：无法获取 DRIVE_CURRENT_FEEDBACK 值!"
    {% endif %}
    
    G1 Z15 F3000
    
    # 执行Eddy有效距离校准
    G1 Z10 F3000
    RESPOND TYPE=command MSG="请执行手动Z偏移校准!"
    SET_KINEMATIC_POSITION Z=10
    PROBE_EDDY_CURRENT_CALIBRATE CHIP=fly_eddy_probe 

    # 提示校准完成
    RESPOND TYPE=command MSG="已完成所有校准流程!"
EOF
)

GCODE_MACRO_TEMP_COMPENSATION=$(cat <<EOF
[gcode_macro TEMP_COMPENSATION]
description: 温度补偿校准流程
gcode:
  {% set bed_temp = params.BED_TEMP|default(80)|int %}
  {% set nozzle_temp = params.NOZZLE_TEMP|default(250)|int %}
  {% set temperature_range_value = params.TEMPERATURE_RANGE_VALUE|default(3)|int %}
  {% set desired_temperature = params.DESIRED_TEMPERATURE|default(70)|int %}
  {% set Temperature_Timeout_Duration = params.TEMPERATURE_TIMEOUT_DURATION|default(6500000000)|int %}
    # 安全检查:确保所有轴未锁定
    {% if printer.pause_resume.is_paused %}
        { action_raise_error("错误：打印机处于暂停状态，请先恢复使能") }
    {% endif %}
    # 第一步:归位所有轴
    RESPOND TYPE=command MSG="正在归位所有轴..."
    G28
    RESPOND TYPE=command MSG="归位完成!"
    # 第二步:自动调平
    Z_TILT_ADJUST
    G0 X{printer.toolhead.axis_maximum.x / 2} Y{printer.toolhead.axis_maximum.y / 2} F6000
    # 第三步:Z轴安全抬升
    RESPOND TYPE=command MSG="Z轴抬升中..."
    G90
    G0 Z5 F2000  # 以较慢速度抬升防止碰撞
    # 第四步:设置超时和温度校准
    SET_IDLE_TIMEOUT TIMEOUT={Temperature_Timeout_Duration}
    RESPOND TYPE=command MSG="开始温度探头校准..."
    TEMPERATURE_PROBE_CALIBRATE PROBE=fly_eddy_probe TARGET={desired_temperature} STEP={temperature_range_value}
    # 第五步:设置打印温度（根据实际需求修改）
    RESPOND TYPE=command MSG="设置工作温度..."
    SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET={bed_temp}
    SET_HEATER_TEMPERATURE HEATER=extruder TARGET={nozzle_temp}
    # 完成提示
    RESPOND TYPE=command MSG="温度补偿流程完成!"
    description: G-Code macro
EOF
)

GCODE_MACRO_BED_MESH_CALIBRATE=$(cat <<EOF
[gcode_macro BED_MESH_CALIBRATE]
rename_existing: _BED_MESH_CALIBRATE
gcode: 
    # ========== LED灯效  ==========
    _status_meshing

    # ========== 扫床流程 ==========
    _BED_MESH_CALIBRATE horizontal_move_z=2 METHOD=rapid_scan {rawparams}
    G28 X Y
EOF
)


GCODE_MACRO_Z_TILT_ADJUST=$(cat <<EOF
[gcode_macro Z_TILT_ADJUST]
rename_existing: _Z_TILT_ADJUST
gcode:
    # ========== LED灯效  ==========
    _status_leveling

    # ========== 状态保存 ==========
    SAVE_GCODE_STATE NAME=STATE_Z_TILT
    
    # ========== 环境准备 ==========
    BED_MESH_CLEAR                       # 清除旧床网数据 
    
    # ========== 主调平流程 ==========
    {% if not printer.z_tilt.applied %}
        # 首次快速粗调 
        _Z_TILT_ADJUST horizontal_move_z=10 retry_tolerance=1
        G0 Z10 F6000                     # 使用标准 G-code 命令替代 HORIZONTAL_MOVE_Z
    {% endif %}
    
    # 精确二次调平 
     _Z_TILT_ADJUST horizontal_move_z=2 retry_tolerance=0.005 retries=20 METHOD=rapid_scan ADAPTIVE=1
        G0 Z10 F6000                     # 使用标准 G-code 命令替代 HORIZONTAL_MOVE_Z
    # ========== 后处理 ==========
    G90                                 # 强制绝对坐标模式 
    G0 Z10 F6000                        # 抬升Z轴到安全高度 
    RESPOND TYPE=command MSG="3Z调平完成!" 
    # ========== 状态恢复 ==========
    RESTORE_GCODE_STATE NAME=STATE_Z_TILT
    M400            
EOF
)


SAVE_VARIABLES=$(cat <<EOF
# [save_variables]
# filename: ~/printer_data/config/variables.cfg
EOF
)

DELAYED_GCODE_RESTORE_PROBE_OFFSET=$(cat <<EOF
# [delayed_gcode RESTORE_PROBE_OFFSET]
# initial_duration: 1.
# gcode:
#   {% set svv = printer.save_variables.variables %}
#   {% if not printer["gcode_macro SET_GCODE_OFFSET"].restored %}
#     SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=runtime_offset VALUE={ svv.nvm_offset|default(0) }
#     SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=restored VALUE=True
#   {% endif %}
EOF
)

GCODE_MACRO_G28=$(cat <<EOF
# [gcode_macro G28]
# rename_existing: G28.1
# gcode:
#   G28.1 {rawparams}
#   {% if not rawparams or (rawparams and 'Z' in rawparams) %}
#     PROBE
#     SET_Z_FROM_PROBE
#   {% endif %}
EOF
)

GCODE_MACRO_SET_Z_FROM_PROBE=$(cat <<EOF
# [gcode_macro SET_Z_FROM_PROBE]
# gcode:
#     {% set cf = printer.configfile.settings %}
#     SET_GCODE_OFFSET_ORIG Z={printer.probe.last_z_result - cf['probe_eddy_current fly_eddy_probe'].z_offset + printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset}
#     G90
#     G1 Z{cf.safe_z_home.z_hop}
EOF
)

GCODE_MACRO_Z_OFFSET_APPLY_PROBE=$(cat <<EOF
# [gcode_macro Z_OFFSET_APPLY_PROBE]
# rename_existing: Z_OFFSET_APPLY_PROBE_ORIG
# gcode:
#   SAVE_VARIABLE VARIABLE=nvm_offset VALUE={ printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset }
EOF
)

GCODE_MACRO_SET_GCODE_OFFSET=$(cat <<EOF
# [gcode_macro SET_GCODE_OFFSET]
# rename_existing: SET_GCODE_OFFSET_ORIG
# variable_restored: False  # Mark whether the var has been restored from NVM
# variable_runtime_offset: 0
# gcode:
#   {% if params.Z_ADJUST %}
#     SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=runtime_offset VALUE={ printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset + params.Z_ADJUST|float }
#   {% endif %}
#   {% if params.Z %} 
#     {% set paramList = rawparams.split() %}
#     {% for i in range(paramList|length) %}
#       {% if paramList[i]=="Z=0" %}
#         {% set temp=paramList.pop(i) %}
#         {% set temp="Z_ADJUST=" + (-printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset)|string %}
#         {% if paramList.append(temp) %}{% endif %}
#       {% endif %}
#     {% endfor %}
#     {% set rawparams=paramList|join(' ') %}
#     SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=runtime_offset VALUE=0
#   {% endif %}
#   SET_GCODE_OFFSET_ORIG { rawparams }
EOF
)

# ================================
# 功能 1: 检查并删除 eddypz.cfg（如果存在），然后重新创建并添加配置内容
# ================================

echo "检查 eddypz.cfg 文件..."

if [ -f "$EDDPZ_CFG" ]; then
    echo "文件存在: $EDDPZ_CFG"
    read -p "是否删除现有的 eddypz.cfg 文件并重新创建？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm "$EDDPZ_CFG"
        echo "已删除文件: $EDDPZ_CFG"
    else
        echo "操作已取消。脚本终止。"
        exit 0
    fi
fi

# 创建新的 eddypz.cfg 并添加配置内容
touch "$EDDPZ_CFG"
add_config() {
    local config_name=$1
    local config_content=$2

    echo "处理配置块: $config_name"
    IFS=$'\n' read -r -d '' -a LINES <<< "$config_content"

    for LINE in "${LINES[@]}"; do
        # 去除行首尾的空白字符，并转义可能的特殊字符
        LINE_CLEAN=$(echo "$LINE" | sed 's/[][\.^$*]/\\&/g' | xargs)
        
        # 使用grep检查整行是否已存在（忽略前后空白字符）
        if ! grep -Fxq "^${LINE_CLEAN}$" "$EDDPZ_CFG"; then
            echo "$LINE" >> "$EDDPZ_CFG"
            echo "已添加: $LINE"
        else
            echo "已存在，跳过: $LINE"
        fi
    done

    # 在每个配置块后添加一个空行，确保最后一个配置块后也有空行
    if ! grep -qxE '' "$EDDPZ_CFG"; then
        echo "" >> "$EDDPZ_CFG"
        echo "已添加空行"
    fi
}

# 添加各个配置块
add_config "probe_eddy_current" "$PROBE_EDDY_CURRENT"
add_config "temperature_probe" "$TEMPERATURE_PROBE"
add_config "gcode_macro_CALIBRATE_EDDY" "$GCODE_MACRO_CALIBRATE_EDDY"
add_config "gcode_macro_TEMP_COMPENSATION" "$GCODE_MACRO_TEMP_COMPENSATION"
add_config "gcode_macro_CANCEL_TEMP_COMPENSATION" "$GCODE_MACRO_CANCEL_TEMP_COMPENSATION"
add_config "gcode_macro_BED_MESH_CALIBRATE" "$GCODE_MACRO_BED_MESH_CALIBRATE"
add_config "gcode_macro_Z_TILT_ADJUST" "$GCODE_MACRO_Z_TILT_ADJUST"
add_config "force_move" "$FORCE_MOVE"
add_config "gcode_macro_CALIBRATE_DD" "$GCODE_MACRO_CALIBRATE_DD"
add_config "save_variables" "$SAVE_VARIABLES"
add_config "delayed_gcode RESTORE_PROBE_OFFSET" "$DELAYED_GCODE_RESTORE_PROBE_OFFSET"
add_config "gcode_macro_G28" "$GCODE_MACRO_G28"
add_config "gcode_macro_SET_Z_FROM_PROBE" "$GCODE_MACRO_SET_Z_FROM_PROBE"
add_config "gcode_macro_Z_OFFSET_APPLY_PROBE" "$GCODE_MACRO_Z_OFFSET_APPLY_PROBE"
add_config "gcode_macro_SET_GCODE_OFFSET" "$GCODE_MACRO_SET_GCODE_OFFSET"
echo "eddypz.cfg 文件已更新。"

# ================================
# 功能 2: 在 printer.cfg 中添加 [include eddypz.cfg] #eddy配置（如果尚未存在）
# ================================
# 检查 printer.cfg 是否存在
if [ ! -f "$PRINTER_CFG" ]; then
    echo "目标文件不存在: $PRINTER_CFG"
    touch "$PRINTER_CFG"
    echo "已创建新文件: $PRINTER_CFG"
fi

# 规范化行尾字符，防止因 Windows 行尾导致的匹配失败
# 使用 sed 进行行尾转换，兼容更多 Linux 发行版
sed -i 's/\r$//' "$PRINTER_CFG"

# 定义要查找的内容，使用正则表达式允许前后有空白字符，并忽略大小写
# 修正了 $$ 为单个 $，并转义了特殊字符
SEARCH_PATTERN='^\s*$$include\s+eddypz\.cfg$$\s*#\s*eddy配置\s*$'
SEARCH_PATTER='^\s*$$probe_eddy_current\s+fly_eddy_probe$$\s*$'

# 检查是否已经包含 [include eddypz.cfg] #eddyconfig
if grep -Eiq "$SEARCH_PATTERN" "$PRINTER_CFG"; then
    echo "[include eddypz.cfg] #eddy配置 已存在于 $PRINTER_CFG 中，跳过添加。"
else
    # 在文件开头插入新行
    sed -i "1i$PRINTER_CFG_CONTENT" "$PRINTER_CFG"
    echo "已添加 [include eddypz.cfg] #eddy配置 到 $PRINTER_CFG 的第一行"
fi

if grep -Eiq "$SEARCH_PATTER" "$PRINTER_CFG"; then
    echo "[probe_eddy_current fly_eddy_probe] 已存在于 $PRINTER_CFG 中，跳过添加。"
else
    # 在文件开头插入新行
    sed -i "2i$PRINTER_CFG_CONTEN" "$PRINTER_CFG"
    echo "已添加 [probe_eddy_current fly_eddy_probe] 到 $PRINTER_CFG 的第三行"
fi

echo "所有操作已完成."
# 在原脚本的最后一行添加
echo "正在重启 Klipper 服务..."
sudo systemctl restart klipper

# 检查重启是否成功
if systemctl is-active --quiet klipper; then
    echo "Klipper 服务已成功重启。"
else
    echo "Klipper 服务重启失败，请检查日志以获取更多信息。"
    exit 1
fi


# 错误处理函数：输出错误信息并退出
error_exit() {
    echo "错误: $1" >&2
    exit 1
}

# 检查文件是否存在
if [ ! -f "$FILE" ]; then
    error_exit "文件 '$FILE' 不存在。"
fi

# 检查文件是否可写
if [ ! -w "$FILE" ]; then
    error_exit "文件 '$FILE' 不可写。请检查权限。"
fi

# 备份原始文件
cp "$FILE" "${FILE}.bak" || error_exit "无法备份文件 '$FILE'。"

# 执行替换操作
sed -i 's/LDC1612_FREQ = 12000000/LDC1612_FREQ = 40000000/g' "$FILE" || error_exit "替换操作失败。"

# 检查替换是否成功
if grep -q "^LDC1612_FREQ = 40000000$" "$FILE"; then
    echo "替换成功：已找到 'LDC1612_FREQ = 40000000'。"
else
    echo "警告：未找到 'LDC1612_FREQ = 40000000'。" >&2
fi

