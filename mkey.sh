#!/bin/sh
#=================================================
#   System Required: OpenHarmony (M-Robots)
#   Description: M-Robots 一键启动管理脚本
#   Based on: spark_noetic / onekey.sh
#   Site: https://github.com/NiMobushimo/spark_noetic
#=================================================

# --- 脚本版本 ---
sh_ver="1.0"

# --- 颜色定义 ---
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Yellow_font_prefix="\033[1;33m"
Blue_font_prefix="\033[0;34m"
Font_color_suffix="\033[0m"

# --- 消息前缀 ---
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Warn="${Yellow_font_prefix}[警告]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"
Separator="——————————————————————————————————————————————"

# --- 全局变量 ---
CAMERATYPE="d435"
LIDARTYPE="ydlidar_g6"
ARMTYPE="uarm"
XVFB_PID=""
X11VNC_PID=""
DISPLAY_NUM=":0"

# =================================================
# 工具函数
# =================================================

# 打印执行命令（高亮显示）
print_command() {
    printf "${Yellow_font_prefix}>>> ${Green_font_prefix}%s${Font_color_suffix}\n" "$1"
}

# 等待用户按回车（OpenHarmony sh 不支持 read -p）
press_enter() {
    printf "%s" "$1"
    read _dummy
}

# 清理并退出（Ctrl+C 或正常退出时调用）
cleanup() {
    printf "\n"
    printf "${Info} 正在停止所有 ROS 节点...\n"
    run busybox killall -9 rosmaster rosout > /dev/null 2>&1
    printf "${Info} 正在关闭虚拟屏幕 (Xvfb) 和 X11VNC 服务...\n"
    if [ -n "$XVFB_PID" ]; then
        kill "$XVFB_PID" > /dev/null 2>&1
        printf "${Info} Xvfb (PID: %s) 已关闭。\n" "$XVFB_PID"
    fi
    if [ -n "$X11VNC_PID" ]; then
        kill "$X11VNC_PID" > /dev/null 2>&1
        printf "${Info} X11VNC (PID: %s) 已关闭。\n" "$X11VNC_PID"
    fi
    printf "${Info} 清理完成，脚本已退出。\n"
    # stty 属于 busybox，OpenHarmony toybox 中不可用，忽略错误
    run busybox stty sane 2>/dev/null || true
    exit 0
}

# 捕获 Ctrl+C (INT) 和终止信号 (TERM)
trap cleanup INT TERM

# =================================================
# 环境初始化
# =================================================

# 检查并挂载文件系统（开发板首次启动需要）
check_mount() {
    if ! touch /data/local/release/.write_test > /dev/null 2>&1; then
        printf "${Info} 检测到文件系统为只读，正在重新挂载...\n"
        mount -o remount,rw /
    else
        rm -f /data/local/release/.write_test
    fi
}

# 获取本机 IP（使用 busybox ip/ifconfig + cut/grep）
get_local_ip() {
    _ip=""
    # 优先尝试 busybox ip addr
    _ip=$(run busybox ip addr 2>/dev/null \
        | run busybox grep "inet " \
        | run busybox grep -v "127.0.0.1" \
        | run busybox head -1 \
        | run busybox tr -s ' ' \
        | run busybox cut -d' ' -f3 \
        | run busybox cut -d'/' -f1)
    # 备选：busybox ifconfig（旧格式 inet addr:x.x.x.x）
    if [ -z "$_ip" ]; then
        _ip=$(run busybox ifconfig 2>/dev/null \
            | run busybox grep "inet addr" \
            | run busybox grep -v "127.0.0.1" \
            | run busybox head -1 \
            | run busybox cut -d':' -f2 \
            | run busybox cut -d' ' -f1)
    fi
    # 备选：busybox ifconfig（新格式 inet x.x.x.x）
    if [ -z "$_ip" ]; then
        _ip=$(run busybox ifconfig 2>/dev/null \
            | run busybox grep "inet " \
            | run busybox grep -v "127.0.0.1" \
            | run busybox head -1 \
            | run busybox tr -s ' ' \
            | run busybox cut -d' ' -f3)
    fi
    printf "%s" "${_ip:-未知}"
}

# 启动虚拟屏幕和 VNC 服务
start_virtual_screen() {
    printf "${Separator}\n"
    printf "${Info} 正在初始化图形显示环境...\n"
    printf "${Separator}\n"

    # 检查 Xvfb 是否已在运行（pgrep 属于 busybox）
    if run busybox pgrep -x "Xvfb" > /dev/null 2>&1; then
        printf "${Tip} 检测到 Xvfb 已在运行，跳过启动。\n"
    else
        printf "${Info} 正在启动 X Virtual Framebuffer (Xvfb)...\n"
        run startxvfb -screen 0 1400x1000x24 &
        XVFB_PID=$!
        sleep 2
        printf "${Info} Xvfb 已启动 (PID: %s)。\n" "$XVFB_PID"
    fi

    # 检查 x11vnc 是否已在运行（pgrep 属于 busybox）
    if run busybox pgrep -x "x11vnc" > /dev/null 2>&1; then
        printf "${Tip} 检测到 X11VNC 已在运行，跳过启动。\n"
    else
        printf "${Info} 正在启动 X11VNC 服务...\n"
        run x11vnc -display ${DISPLAY_NUM} -forever -shared > /dev/null 2>&1 &
        X11VNC_PID=$!
        sleep 2
        printf "${Info} X11VNC 已启动 (PID: %s)。\n" "$X11VNC_PID"
    fi

    _local_ip=$(get_local_ip)
    printf "\n"
    printf "${Info} ${Green_font_prefix}图形显示环境已就绪！${Font_color_suffix}\n"
    printf "${Tip} 请使用 VNC 客户端连接至: ${Yellow_font_prefix}%s:5900${Font_color_suffix}\n" "$_local_ip"
    printf "${Tip} 所有带 RVIZ 的功能将在 VNC 窗口中显示。\n"
    printf "${Separator}\n"
    sleep 1
}

# =================================================
# 设备检查
# =================================================

# 检查设备连接（通过软链接判断，适配 OpenHarmony）
check_dev() {
    printf "${Separator}\n"
    printf "${Info} 正在检查设备连接状态...\n"
    printf "${Separator}\n"

    # 检查底盘（readlink 属于 busybox）
    if [ -L "/dev/sparkBase" ] && [ -e "/dev/sparkBase" ]; then
        printf "${Info} ${Green_font_prefix}底盘已连接${Font_color_suffix}: /dev/sparkBase -> %s\n" \
            "$(run busybox readlink /dev/sparkBase)"
    elif [ -L "/dev/sparkBase" ]; then
        printf "${Error} 底盘软链接存在但设备已断开，请重新连接！(/dev/sparkBase)\n"
    else
        printf "${Error} 底盘未连接，请检查 /dev/sparkBase 软链接！(usbRules.sh 守护进程是否运行?)\n"
    fi

    # 检查激光雷达（readlink 属于 busybox）
    if [ -L "/dev/ydlidar" ] && [ -e "/dev/ydlidar" ]; then
        printf "${Info} ${Green_font_prefix}激光雷达已连接${Font_color_suffix}: /dev/ydlidar -> %s\n" \
            "$(run busybox readlink /dev/ydlidar)"
        LIDARTYPE="ydlidar_g6"
    elif [ -L "/dev/ydlidar" ]; then
        printf "${Error} 激光雷达软链接存在但设备已断开，请重新连接！(/dev/ydlidar)\n"
        LIDARTYPE="ydlidar_g6"
    else
        printf "${Error} 激光雷达未连接，请检查 /dev/ydlidar 软链接！\n"
        LIDARTYPE="ydlidar_g6"
    fi

    # 检查机械臂（readlink 属于 busybox）
    if [ -L "/dev/uarm" ] && [ -e "/dev/uarm" ]; then
        printf "${Info} ${Green_font_prefix}机械臂 (uArm) 已连接${Font_color_suffix}: /dev/uarm -> %s\n" \
            "$(run busybox readlink /dev/uarm)"
        ARMTYPE="uarm"
    elif [ -L "/dev/uarm" ]; then
        printf "${Warn} 机械臂软链接存在但设备已断开，请检查机械臂是否上电！(/dev/uarm)\n"
        ARMTYPE="uarm"
    else
        printf "${Warn} 未检测到机械臂 (/dev/uarm)，部分功能将不可用。\n"
        ARMTYPE="uarm"
    fi

    # 摄像头（深度摄像头通过 USB 直连，不使用串口软链接）
    # ls 在 toybox 和 busybox 中均可用，此处直接使用
    if ls /dev/video* > /dev/null 2>&1; then
        printf "${Info} ${Green_font_prefix}摄像头已检测到${Font_color_suffix} (类型: %s)\n" "$CAMERATYPE"
    else
        printf "${Warn} 未检测到摄像头设备 (/dev/video*)，请确认摄像头已连接！\n"
        printf "${Warn} ${Red_font_prefix}注意: 摄像头不可通过 USB 拓展坞连接开发板！${Font_color_suffix}\n"
    fi

    printf "${Separator}\n"
}

# =================================================
# 功能函数
# =================================================

# 1. 让机器人动起来（键盘控制）
let_robot_go() {
    printf "${Info}\n"
    printf "${Info} 让机器人动起来 (键盘控制 + RVIZ 可视化)\n"
    printf "${Separator}\n"
    printf "${Tip} 底盘控制说明：\n"
    printf "${Tip}   要控制底盘移动，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 并执行:\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}\n"
    printf "${Tip} 键盘方向对应：\n"
    printf "${Tip}           w 前进           \n"
    printf "${Tip}   a 左转         d 右转   \n"
    printf "${Tip}           s 后退           \n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始启动主程序（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_teleop teleop.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE} arm_type_tel:=${ARMTYPE} enable_arm_tel:='yes'"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_teleop teleop.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE} \
        arm_type_tel:=${ARMTYPE} \
        enable_arm_tel:='yes'
}

# 2. 手眼标定
hand_eye_calibration() {
    printf "${Info}\n"
    printf "${Info} 手眼标定\n"
    printf "${Separator}\n"
    printf "${Tip} 请确认以下事项后再继续：\n"
    printf "${Tip}   A. 摄像头已反向向下安装好。\n"
    printf "${Tip}   B. 机械臂已正常上电。\n"
    printf "${Tip}   C. 标定程序启动后，请在 VNC 窗口中查看相机视角并调整角度。\n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_cal_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_cal_cv3.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
    printf "\n"
    printf "${Info} 程序启动后，请在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令以触发标定:\n"
    printf "${Info} ${Green_font_prefix}run rostopic pub /start_topic std_msgs/String \"data: 'start'\"${Font_color_suffix}\n"
}

# 3. 物品抓取
object_grasping() {
    printf "${Info}\n"
    printf "${Info} 物品抓取\n"
    printf "${Separator}\n"
    printf "${Tip} 请确认以下事项后再继续：\n"
    printf "${Tip}   A. 已完成手眼标定，标定文件已保存至正确路径。\n"
    printf "${Tip}   B. 机械臂已正常上电。\n"
    printf "${Tip}   C. 已准备好目标物品。\n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_object_only_cv3.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_carry_object spark_carry_object_only_cv3.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
    printf "\n"
    printf "${Info} 程序启动后，请在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令以开始抓取:\n"
    printf "${Info} ${Green_font_prefix}run rosservice call /s_carry_object 'type: 1'${Font_color_suffix}\n"
}

# 4. 激光雷达建图（gmapping）
build_map_lidar() {
    printf "${Info}\n"
    printf "${Info} 激光雷达建图 (GMapping)\n"
    printf "${Separator}\n"
    printf "${Tip} 请确认以下事项后再继续：\n"
    printf "${Tip}   A. 激光雷达已上电并正确连接 (/dev/ydlidar)。\n"
    printf "${Tip}   B. 底盘已正确连接 (/dev/sparkBase)。\n"
    printf "${Tip} ${Yellow_font_prefix}底盘控制提示:${Font_color_suffix}\n"
    printf "${Tip}   建图过程中，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 执行以下命令控制底盘:\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}\n"
    printf "${Tip}   键盘 wsad 分别对应 前/后/左/右。\n"
    printf "${Tip} ${Yellow_font_prefix}保存地图:${Font_color_suffix}\n"
    printf "${Tip}   建图完成后，在 ${Yellow_font_prefix}新终端${Font_color_suffix} 中执行以下命令保存地图:\n"
    printf "${Tip}   ${Green_font_prefix}mkdir -p /data/local/release/usr/share/spark_slam/scripts${Font_color_suffix}\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch map_server map_server.launch${Font_color_suffix}\n"
    printf "${Tip}   更多建图方式敬请期待...\n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam 2d_slam_teleop.launch slam_methods_tel:=gmapping camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_slam 2d_slam_teleop.launch \
        slam_methods_tel:="gmapping" \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
}

# 5. 深度摄像头建图（RTAB-Map）
build_map_camera() {
    printf "${Info}\n"
    printf "${Info} 深度摄像头建图 (RTAB-Map)\n"
    printf "${Separator}\n"
    printf "${Tip} 请确认以下事项后再继续：\n"
    printf "${Tip}   A. 深度摄像头 (%s) 已正确连接（不可通过 USB 拓展坞）。\n" "$CAMERATYPE"
    printf "${Tip}   B. 底盘已正确连接 (/dev/sparkBase)。\n"
    printf "${Tip} ${Yellow_font_prefix}底盘控制提示:${Font_color_suffix}\n"
    printf "${Tip}   建图过程中，需要在 ${Yellow_font_prefix}MobaXterm 中另开一个终端${Font_color_suffix} 执行以下命令控制底盘:\n"
    printf "${Tip}   ${Green_font_prefix}run roslaunch spark_teleop teleop_only.launch${Font_color_suffix}\n"
    printf "${Tip}   键盘 wsad 分别对应 前/后/左/右。\n"
    printf "${Tip} ${Yellow_font_prefix}地图保存:${Font_color_suffix}\n"
    printf "${Tip}   建图完成后，地图数据库将自动保存至: /data/local/release/rtabmap.db\n"
    printf "${Tip}   更多建图方式敬请期待...\n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_teleop.launch camera_type_tel:=${CAMERATYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_teleop.launch \
        camera_type_tel:=${CAMERATYPE}
}

# 6. 激光雷达导航
navigation_lidar() {
    printf "${Info}\n"
    printf "${Info} 激光雷达导航 (AMCL)\n"
    printf "${Separator}\n"
    printf "${Tip} 请确认以下事项后再继续：\n"
    printf "${Tip}   A. 激光雷达已上电并正确连接 (/dev/ydlidar)。\n"
    printf "${Tip}   B. 已有建图阶段保存的地图文件 (test_map.yaml / test_map.pgm)。\n"
    printf "${Tip} ${Yellow_font_prefix}导航操作说明:${Font_color_suffix}\n"
    printf "${Tip}   1. 导航启动后，在 VNC 的 RVIZ 中点击 '2D Pose Estimate' 并在地图上手动初始化机器人位置。\n"
    printf "${Tip}   2. 初始化成功后，点击 '2D Nav Goal' 并在地图上指定导航目标点，机器人将自主导航。\n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_lidar_rviz.launch camera_type_tel:=${CAMERATYPE} lidar_type_tel:=${LIDARTYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_navigation amcl_demo_lidar_rviz.launch \
        camera_type_tel:=${CAMERATYPE} \
        lidar_type_tel:=${LIDARTYPE}
}

# 7. 深度摄像头导航
navigation_camera() {
    printf "${Info}\n"
    printf "${Info} 深度摄像头导航 (RTAB-Map)\n"
    printf "${Separator}\n"
    printf "${Tip} 请确认以下事项后再继续：\n"
    printf "${Tip}   A. 深度摄像头 (%s) 已正确连接（不可通过 USB 拓展坞）。\n" "$CAMERATYPE"
    printf "${Tip}   B. 已有建图阶段保存的地图数据库 (/data/local/release/rtabmap.db)。\n"
    printf "${Tip}   C. 请将机器人放置在建图时的起始点位置。\n"
    printf "${Tip} ${Yellow_font_prefix}导航操作说明:${Font_color_suffix}\n"
    printf "${Tip}   导航启动后，在 VNC 的 RVIZ 中点击 '2D Nav Goal' 并在地图上指定导航目标点。\n"
    printf "${Tip}   如需加载 3D 地图，点击 RVIZ 中 Display -> Rtabmap cloud -> Download map。\n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_nav.launch camera_type_tel:=${CAMERATYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_rtabmap spark_rtabmap_nav.launch \
        camera_type_tel:=${CAMERATYPE}
}

# 8. 深度跟随
depth_follow() {
    printf "${Info}\n"
    printf "${Info} 深度跟随\n"
    printf "${Separator}\n"
    printf "${Tip} 请确认以下事项后再继续：\n"
    printf "${Tip}   A. 深度摄像头 (%s) 已正确连接。\n" "$CAMERATYPE"
    printf "${Tip}   B. ${Red_font_prefix}摄像头不可通过 USB 拓展坞连接开发板，否则无法正常使用！${Font_color_suffix}\n"
    printf "${Tip}   C. 启动后，请站在机器人正前方约 1 米处，机器人将自动跟随您移动。\n"
    printf "${Separator}\n"
    press_enter "按回车键（Enter）开始（RVIZ 将在 VNC 窗口中显示）: "
    print_command "DISPLAY=${DISPLAY_NUM} run roslaunch spark_follower bringup.launch camera_type_tel:=${CAMERATYPE}"
    DISPLAY=${DISPLAY_NUM} run roslaunch spark_follower bringup.launch \
        camera_type_tel:=${CAMERATYPE}
}

# =================================================
# 主菜单
# =================================================

show_menu() {
    clear
    printf "\n"
    printf "${Separator}\n"
    printf "  M-Robots (OpenHarmony) 一键启动脚本 ${Red_font_prefix}[v%s]${Font_color_suffix}\n" "$sh_ver"
    printf "  基于 spark_noetic 移植 | 请根据功能说明选择序号\n"
    printf "${Separator}\n"
    printf "\n"
    printf "  ${Green_font_prefix}基础功能${Font_color_suffix}\n"
    printf "  ${Green_font_prefix}  1.${Font_color_suffix} 让机器人动起来 (键盘控制 + RVIZ)\n"
    printf "  ${Green_font_prefix}  2.${Font_color_suffix} 手眼标定\n"
    printf "  ${Green_font_prefix}  3.${Font_color_suffix} 物品抓取\n"
    printf "\n"
    printf "  ${Green_font_prefix}建图功能${Font_color_suffix}\n"
    printf "  ${Green_font_prefix}  4.${Font_color_suffix} 激光雷达建图 (GMapping)\n"
    printf "  ${Green_font_prefix}  5.${Font_color_suffix} 深度摄像头建图 (RTAB-Map)\n"
    printf "         ${Blue_font_prefix}更多建图方式敬请期待...${Font_color_suffix}\n"
    printf "\n"
    printf "  ${Green_font_prefix}导航功能${Font_color_suffix}\n"
    printf "  ${Green_font_prefix}  6.${Font_color_suffix} 激光雷达导航 (AMCL)\n"
    printf "  ${Green_font_prefix}  7.${Font_color_suffix} 深度摄像头导航 (RTAB-Map)\n"
    printf "\n"
    printf "  ${Green_font_prefix}应用功能${Font_color_suffix}\n"
    printf "  ${Green_font_prefix}  8.${Font_color_suffix} 深度跟随\n"
    printf "\n"
    printf "${Separator}\n"
    printf "  ${Green_font_prefix}  0.${Font_color_suffix} 退出脚本（将同时关闭 Xvfb 和 X11VNC）\n"
    printf "${Separator}\n"
    check_dev
}

# =================================================
# 脚本入口
# =================================================

# 第一步：检查并挂载文件系统
check_mount

# 第二步：启动虚拟屏幕和 VNC 服务
start_virtual_screen

# 第三步：进入主循环
while true; do
    show_menu
    printf "请输入数字 [0-8]: "
    read num
    case "$num" in
        1)
            let_robot_go
            ;;
        2)
            hand_eye_calibration
            ;;
        3)
            object_grasping
            ;;
        4)
            build_map_lidar
            ;;
        5)
            build_map_camera
            ;;
        6)
            navigation_lidar
            ;;
        7)
            navigation_camera
            ;;
        8)
            depth_follow
            ;;
        0)
            cleanup
            ;;
        *)
            printf "${Error} 请输入正确的数字 [0-8]\n"
            ;;
    esac
    printf "\n"
    printf "${Info} 功能已结束，按回车键返回主菜单...\n"
    read _dummy
done
