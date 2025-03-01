#!/bin/bash

# ====================================================
# 脚本名称: setup_printer_config.sh
# 功能:
#   1. 检查并删除 ~/printer_data/config/eddypz.cfg（如果存在），然后重新创建并添加配置内容。
#   2. 在 ~/printer_data/config/printer.cfg 文件的第一行添加 [include eddypz.cfg] #eddy配置（如果尚未存在）。

# ====================================================


# 设置目标文件路径
PRINTER_CFG="$HOME/printer_data/config/printer.cfg"
EDDPZ_CFG="$HOME/printer_data/config/eddypz.cfg"
FILE="$HOME/klipper/klippy/extras/ldc1612.py"

# 定义要添加到 printer.cfg 的内容
PRINTER_CFG_CONTENT="[include eddypz.cfg]"
PRINTER_CFG_CONTEN="[probe_eddy_current fly_eddy_probe]\nz_offset: 2.0"

# 定义要添加到 eddypz.cfg 的内容，分开处理
PROBE_EDDY_CURRENT=$(cat <<EOF
[probe_eddy_current fly_eddy_probe]
sensor_type: ldc1612
i2c_address: 43
i2c_mcu: SHT36
i2c_bus: i2c1e
x_offset: 0 #记得设置x偏移
y_offset: 0 #记得设置y偏移 
speed:40
lift_speed: 15.0
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
description: 执行Eddy电流传感器校准及后续调平流程 
gcode:
    # ========== 开始校准 Eddy 电流传感器 ==========
    M117 开始校准 Eddy 电流传感器...

    # 安全检测：检查打印机是否处于暂停状态
    {% if printer.pause_resume.is_paused|lower == 'true' %}
        {action_raise_error("校准前请先恢复打印状态")}
    {% endif %}

    # 归零X/Y轴 
    G28 X Y 

    # 移动打印头到热床中心（适配多数CoreXY机型）
    G0 X{printer.toolhead.axis_maximum.x / 2} Y{printer.toolhead.axis_maximum.y / 2} F6000 
    
    SET_KINEMATIC_POSITION X={printer.toolhead.axis_maximum.x / 2} Y={printer.toolhead.axis_maximum.y / 2} Z={printer.toolhead.axis_maximum.z-10}

    # 执行校准流程 
    LDC_CALIBRATE_DRIVE_CURRENT CHIP=fly_eddy_probe 

    # 尝试输出 DRIVE_CURRENT_FEEDBACK 的值
    M117 Eddy 电流校准完成，反馈值: {DRIVE_CURRENT_FEEDBACK}

    # 检查反馈值是否在正常范围内
    {% if DRIVE_CURRENT_FEEDBACK is defined %}
        {% if DRIVE_CURRENT_FEEDBACK < 10 or DRIVE_CURRENT_FEEDBACK > 20 %}
            M117 警告：Eddy 电流反馈值异常（{DRIVE_CURRENT_FEEDBACK}）。请检查连接。
        {% else %}
            M117 Eddy 电流反馈值正常（{DRIVE_CURRENT_FEEDBACK}）。
        {% endif %}
    {% else %}
        M117 错误：无法获取 DRIVE_CURRENT_FEEDBACK 值。
    {% endif %}

    # 提示用户执行手动Z偏移校准
    M117 请执行手动Z偏移校准。

    # 执行Eddy有效距离校准
    PROBE_EDDY_CURRENT_CALIBRATE CHIP=fly_eddy_probe 

    # 提示校准完成
    M117 已完成所有校准流程！
EOF
)

GCODE_MACRO_TEMP_COMPENSATION=$(cat <<EOF
[gcode_macro TEMP_COMPENSATION]
description: 温度补偿校准流程
gcode:
  {% set bed_temp = params.BED_TEMP|default(90)|int %}
  {% set nozzle_temp = params.NOZZLE_TEMP|default(250)|int %}
  {% set min_temp = params.MIN_TEMP|default(40)|int %}
  {% set max_temp = params.MAX_TEMP|default(70)|int %}
  {% set temperature_range_value = params.TEMPERATURE_RANGE_VALUE|default(3)|int %}
  {% set desired_temperature = params.DESIRED_TEMPERATURE|default(80)|int %}
  {% set Temperature_Timeout_Duration = params.TEMPERATURE_TIMEOUT_DURATION|default(6500000000)|int %}
    # 安全检查：确保所有轴未锁定
    {% if printer.pause_resume.is_paused %}
        { action_raise_error("错误：打印机处于暂停状态，请先恢复使能") }
    {% endif %}
    # 第一步：归位所有轴
    STATUS_MESSAGE="正在归位所有轴..."
    G28
    STATUS_MESSAGE="归位完成"
    # 第三步：Z轴安全抬升
    STATUS_MESSAGE="Z轴抬升中..."
    G90
    G0 Z5 F2000  # 以较慢速度抬升防止碰撞
    # 第四步：设置超时和温度校准
    SET_IDLE_TIMEOUT TIMEOUT={Temperature_Timeout_Duration}
    STATUS_MESSAGE="开始温度探头校准..."
    TEMPERATURE_PROBE_CALIBRATE PROBE=fly_eddy_probe TARGET={desired_temperature} STEP={temperature_range_value}
    # 第五步：设置打印温度（根据实际需求修改）
    STATUS_MESSAGE="设置工作温度..."
    SET_HEATER_TEMPERATURE HEATER={nozzle_temp} TARGET={max_temp}
    SET_HEATER_TEMPERATURE HEATER={bed_temp} TARGET={max_temp}
    # 完成提示
    STATUS_MESSAGE="温度补偿流程完成！"
    description: G-Code macro
EOF
)

GCODE_MACRO_CANCEL_TEMP_COMPENSATION=$(cat <<EOF
[gcode_macro CANCEL_TEMP_COMPENSATION]
description: 中止温度补偿流程
gcode:
    SET_IDLE_TIMEOUT TIMEOUT=600  # 恢复默认超时
    TURN_OFF_HEATERS
    M117 校准已中止
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
add_config "force_move" "$FORCE_MOVE"
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
    exit 0
else
    error_exit "替换失败：未找到 'LDC1612_FREQ = 40000000'。"
fi
exit 0
