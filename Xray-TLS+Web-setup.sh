#!/bin/bash

#系统信息
#指令集
machine=""
#什么系统
release=""
#系统版本号
systemVersion=""
redhat_version=""
debian_package_manager=""
redhat_package_manager=""
#物理内存大小
mem=""
#在运行脚本前物理内存+swap大小
mem_total=""
#在运行脚本前是否有启用swap
using_swap=""
#现在有没有通过脚本启动swap
using_swap_now=0

#安装信息
nginx_version="nginx-1.19.6"
openssl_version="openssl-openssl-3.0.0-alpha11"
nginx_prefix="/usr/local/nginx"
nginx_config="${nginx_prefix}/conf.d/xray.conf"
nginx_service="/etc/systemd/system/nginx.service"
nginx_is_installed=""

php_version="php-8.0.1"
php_prefix="/usr/local/php"
php_service="/etc/systemd/system/php-fpm.service"
php_is_installed=""

cloudreve_version="3.2.1"
cloudreve_prefix="/usr/local/cloudreve"
cloudreve_service="/etc/systemd/system/cloudreve.service"
cloudreve_is_installed=""

nextcloud_url="https://download.nextcloud.com/server/prereleases/nextcloud-21.0.0beta8.zip"

xray_config="/usr/local/etc/xray/config.json"
xray_is_installed=""

temp_dir="/temp_install_update_xray_tls_web"

is_installed=""

update=""

#配置信息
#域名列表 两个列表用来区别 www.一级域名
unset domain_list
unset true_domain_list
unset domain_config_list
#域名伪装列表，对应域名列表
unset pretend_list

#Xray-TCP-TLS使用的协议，0代表禁用，1代表VLESS
protocol_1=""
#Xray-WS-TLS使用的协议，0代表禁用，1代表VLESS，2代表VMess
protocol_2=""
path=""
xid_1=""
xid_2=""


#功能性函数：
#定义几个颜色
purple()                           #基佬紫
{
    echo -e "\\033[35;1m${*}\\033[0m"
}
tyblue()                           #天依蓝
{
    echo -e "\\033[36;1m${*}\\033[0m"
}
green()                            #水鸭青
{
    echo -e "\\033[32;1m${*}\\033[0m"
}
yellow()                           #鸭屎黄
{
    echo -e "\\033[33;1m${*}\\033[0m"
}
red()                              #姨妈红
{
    echo -e "\\033[31;1m${*}\\033[0m"
}
#检查基本命令
check_base_command()
{
    local i
    local temp_command_list=('bash' 'true' 'false' 'exit' 'echo' 'test' 'free' 'sort' 'sed' 'awk' 'grep' 'cut' 'cd' 'rm' 'cp' 'mv' 'head' 'tail' 'uname' 'tr' 'md5sum' 'tar' 'cat' 'find' 'type' 'command' 'kill' 'pkill' 'wc' 'ls' 'mktemp')
    for i in ${!temp_command_list[@]}
    do
        if ! command -V "${temp_command_list[$i]}" > /dev/null; then
            red "命令\"${temp_command_list[$i]}\"未找到"
            red "不是标准的Linux系统"
            exit 1
        fi
    done
}
#版本比较函数
version_ge()
{
    test "$(echo -e "$1\\n$2" | sort -rV | head -n 1)" == "$1"
}
#安装单个重要依赖
check_important_dependence_installed()
{
    if [ $release == "ubuntu" ] || [ $release == "other-debian" ]; then
        if dpkg -s "$1" > /dev/null 2>&1; then
            apt-mark manual "$1"
        elif ! $debian_package_manager -y --no-install-recommends install "$1"; then
            $debian_package_manager update
            if ! $debian_package_manager -y --no-install-recommends install "$1"; then
                red "重要组件\"$1\"安装失败！！"
                yellow "按回车键继续或者Ctrl+c退出"
                read -s
            fi
        fi
    else
        if rpm -q "$2" > /dev/null 2>&1; then
            if [ "$redhat_package_manager" == "dnf" ]; then
                dnf mark install "$2"
            else
                yumdb set reason user "$2"
            fi
        elif ! $redhat_package_manager -y install "$2"; then
            red "重要组件\"$2\"安装失败！！"
            yellow "按回车键继续或者Ctrl+c退出"
            read -s
        fi
    fi
}
#安装依赖
install_dependence()
{
    if [ $release == "ubuntu" ] || [ $release == "other-debian" ]; then
        if ! $debian_package_manager -y --no-install-recommends install "$@"; then
            $debian_package_manager update
            if ! $debian_package_manager -y --no-install-recommends install "$@"; then
                yellow "依赖安装失败！！"
                green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
                yellow "按回车键继续或者Ctrl+c退出"
                read -s
            fi
        fi
    else
        if $redhat_package_manager --help | grep -q "\\-\\-enablerepo="; then
            local temp_redhat_install="$redhat_package_manager -y --enablerepo="
        else
            local temp_redhat_install="$redhat_package_manager -y --enablerepo "
        fi
        if ! $redhat_package_manager -y install "$@"; then
            if [ "$release" == "centos" ] && version_ge "$systemVersion" 8 && $temp_redhat_install"epel,PowerTools" install "$@";then
                return 0
            fi
            if $temp_redhat_install'*' install "$@"; then
                return 0
            fi
            yellow "依赖安装失败！！"
            green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
            yellow "按回车键继续或者Ctrl+c退出"
            read -s
        fi
    fi
}
#进入工作目录
enter_temp_dir()
{
    rm -rf "$temp_dir"
    mkdir "$temp_dir"
    cd "$temp_dir"
}
#检查是否需要php
check_need_php()
{
    [ $is_installed -eq 0 ] && return 1
    local i
    for i in ${!pretend_list[@]}
    do
        [ "${pretend_list[$i]}" == "2" ] && return 0
    done
    return 1
}
#检查是否需要cloudreve
check_need_cloudreve()
{
    [ $is_installed -eq 0 ] && return 1
    local i
    for i in ${!pretend_list[@]}
    do
        [ "${pretend_list[$i]}" == "1" ] && return 0
    done
    return 1
}
#检查Nginx更新
check_nginx_update()
{
    local nginx_version_now
    local openssl_version_now
    nginx_version_now="nginx-$(${nginx_prefix}/sbin/nginx -V 2>&1 | grep "^nginx version:" | cut -d / -f 2)"
    openssl_version_now="openssl-openssl-$(${nginx_prefix}/sbin/nginx -V 2>&1 | grep "^built with OpenSSL" | awk '{print $4}')"
    if [ "$nginx_version_now" == "$nginx_version" ] && [ "$openssl_version_now" == "$openssl_version" ]; then
        return 1
    else
        return 0
    fi
}
#检查php更新
check_php_update()
{
    local php_version_now
    php_version_now="php-$(${php_prefix}/bin/php -v | head -n 1 | awk '{print $2}')"
    [ "$php_version_now" == "$php_version" ] && return 1
    return 0
}
swap_on()
{
    if [ $using_swap_now -ne 0 ]; then
        red    "开启swap错误发生"
        green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
        yellow "按回车键继续或者Ctrl+c退出"
        read -s
    fi
    if [ $mem_total -lt $1 ]; then
        tyblue "内存不足$1M，自动申请swap。。"
        if dd if=/dev/zero of=${temp_dir}/swap bs=1M count=$(($1-mem)); then
            chmod 0600 ${temp_dir}/swap
            mkswap ${temp_dir}/swap
            swapoff -a
            swapon ${temp_dir}/swap
            using_swap_now=1
        else
            rm -rf ${temp_dir}/swap
            red   "开启swap失败！"
            yellow "可能是机器内存和硬盘空间都不足"
            green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
            yellow "按回车键继续或者Ctrl+c退出"
            read -s
        fi
    fi
}
swap_off()
{
    if [ $using_swap_now -eq 1 ]; then
        tyblue "正在恢复swap。。。"
        swapoff -a
        [ $using_swap -ne 0 ] && swapon -a
        using_swap_now=0
    fi
}
#启用/禁用php cloudreve
turn_on_off_php()
{
    if check_need_php; then
        systemctl --now enable php-fpm
    else
        systemctl --now disable php-fpm
    fi
}
turn_on_off_cloudreve()
{
    if check_need_cloudreve; then
        systemctl --now enable cloudreve
    else
        systemctl --now disable cloudreve
    fi
}
let_change_cloudreve_domain()
{
    tyblue "----------- 请打开\"https://${domain_list[$1]}\"修改Cloudreve站点信息 ---------"
    tyblue "  1. 登陆帐号"
    tyblue "  2. 右上角头像 -> 管理面板"
    tyblue "  3. 左侧的参数设置 -> 站点信息"
    tyblue "  4. 站点URL改为\"https://${domain_list[$1]}\" -> 往下拉点击保存"
    sleep 15s
    echo -e "\\n\\n"
    tyblue "按两次回车键以继续。。。"
    read -s
    read -s
}
init_cloudreve()
{
    local temp
    temp="$(timeout 5s $cloudreve_prefix/cloudreve | grep "初始管理员密码：" | awk '{print $4}')"
    sleep 1s
    systemctl --now enable cloudreve
    tyblue "-------- 请打开\"https://${domain_list[$1]}\"进行Cloudreve初始化 -------"
    tyblue "  1. 登陆帐号"
    purple "    初始管理员账号：admin@cloudreve.org"
    purple "    $temp"
    tyblue "  2. 右上角头像 -> 管理面板"
    tyblue "  3. 这时会弹出对话框 \"确定站点URL设置\" 选择 \"更改\""
    tyblue "  4. 左侧参数设置 -> 注册与登陆 -> 不允许新用户注册 -> 往下拉点击保存"
    sleep 15s
    echo -e "\\n\\n"
    tyblue "按两次回车键以继续。。。"
    read -s
    read -s
}
ask_if()
{
    local choice=""
    while [ "$choice" != "y" ] && [ "$choice" != "n" ]
    do
        tyblue "$1"
        read choice
    done
    [ $choice == y ] && return 0
    return 1
}
#卸载函数
remove_xray()
{
    if ! bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) remove --purge; then
        systemctl --now disable xray
        rm -rf /usr/local/bin/xray
        rm -rf /usr/local/etc/xray
        rm -rf /etc/systemd/system/xray.service
        rm -rf /etc/systemd/system/xray@.service
        rm -rf /var/log/xray
        systemctl daemon-reload
    fi
}
remove_nginx()
{
    systemctl --now disable nginx
    rm -rf $nginx_service
    systemctl daemon-reload
    rm -rf ${nginx_prefix}
    nginx_is_installed=0
}
remove_php()
{
    systemctl --now disable php-fpm
    rm -rf $php_service
    systemctl daemon-reload
    rm -rf ${php_prefix}
    php_is_installed=0
}
remove_cloudreve()
{
    systemctl --now disable cloudreve
    rm -rf $cloudreve_service
    systemctl daemon-reload
    rm -rf ${cloudreve_prefix}
    cloudreve_is_installed=0
}
#备份域名伪装网站
backup_domains_web()
{
    local i
    mkdir "${temp_dir}/domain_backup"
    for i in ${!true_domain_list[@]}
    do
        if [ "$1" == "cp" ]; then
            cp -rf ${nginx_prefix}/html/${true_domain_list[$i]} "${temp_dir}/domain_backup" 2>/dev/null
        else
            mv ${nginx_prefix}/html/${true_domain_list[$i]} "${temp_dir}/domain_backup" 2>/dev/null
        fi
    done
}
#获取配置信息
get_config_info()
{
    [ $is_installed -eq 0 ] && return
    if [ $(grep -c '"clients"' $xray_config) -eq 2 ] || [ $(grep -Ec '"(vmess|vless)"' $xray_config) -eq 1 ]; then
        protocol_1=1
        xid_1=$(grep '"id"' $xray_config | head -n 1 | cut -d : -f 2)
        xid_1=${xid_1#*'"'}
        xid_1=${xid_1%'"'*}
    else
        protocol_1=0
        xid_1=""
    fi
    if [ $(grep -Ec '"(vmess|vless)"' $xray_config) -eq 2 ]; then
        grep -q '"vmess"' $xray_config && protocol_2=2 || protocol_2=1
        path=$(grep '"path"' $xray_config | head -n 1 | cut -d : -f 2)
        path=${path#*'"'}
        path=${path%'"'*}
        xid_2=$(grep '"id"' $xray_config | tail -n 1 | cut -d : -f 2)
        xid_2=${xid_2#*'"'}
        xid_2=${xid_2%'"'*}
    else
        protocol_2=0
        path=""
        xid_2=""
    fi
    unset domain_list
    unset true_domain_list
    unset domain_config_list
    unset pretend_list
    domain_list=($(grep "^#domain_list=" $nginx_config | cut -d = -f 2))
    true_domain_list=($(grep "^#true_domain_list=" $nginx_config | cut -d = -f 2))
    domain_config_list=($(grep "^#domain_config_list=" $nginx_config | cut -d = -f 2))
    pretend_list=($(grep "^#pretend_list=" $nginx_config | cut -d = -f 2))
}
#删除所有域名
remove_all_domains()
{
    systemctl stop xray
    systemctl stop nginx
    systemctl --now disable php-fpm
    systemctl --now disable cloudreve
    local i
    for i in ${!true_domain_list[@]}
    do
        rm -rf ${nginx_prefix}/html/${true_domain_list[$i]}
    done
    rm -rf "${nginx_prefix}/certs"
    mkdir "${nginx_prefix}/certs"
    $HOME/.acme.sh/acme.sh --uninstall
    rm -rf $HOME/.acme.sh
    curl https://get.acme.sh | sh
    $HOME/.acme.sh/acme.sh --upgrade --auto-upgrade
    unset domain_list
    unset true_domain_list
    unset domain_config_list
    unset pretend_list
}

check_base_command
if [ "$EUID" != "0" ]; then
    red "请用root用户运行此脚本！！"
    exit 1
fi
if [[ ! -f '/etc/os-release' ]]; then
    red "系统版本太老，Xray官方脚本不支持"
    exit 1
fi
if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
    true
elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
    true
else
    red "仅支持使用systemd的系统！"
    exit 1
fi
if [[ ! -d /dev/shm ]]; then
    red "/dev/shm不存在，不支持的系统"
    exit 1
fi
if [[ "$(type -P apt)" ]]; then
    if [[ "$(type -P dnf)" ]] || [[ "$(type -P yum)" ]]; then
        red "同时存在apt和yum/dnf"
        red "不支持的系统！"
        exit 1
    fi
    release="other-debian"
    debian_package_manager="apt"
    redhat_package_manager="true"
elif [[ "$(type -P dnf)" ]]; then
    release="other-redhat"
    redhat_package_manager="dnf"
    debian_package_manager="true"
elif [[ "$(type -P yum)" ]]; then
    release="other-redhat"
    redhat_package_manager="yum"
    debian_package_manager="true"
else
    red "apt yum dnf命令均不存在"
    red "不支持的系统"
    exit 1
fi
[ -e $nginx_config ] && nginx_is_installed=1 || nginx_is_installed=0
[ -e ${php_prefix}/php-fpm.service.default ] && php_is_installed=1 || php_is_installed=0
[ -e ${cloudreve_prefix}/cloudreve.db ] && cloudreve_is_installed=1 || cloudreve_is_installed=0
[ -e /usr/local/bin/xray ] && xray_is_installed=1 || xray_is_installed=0
([ $xray_is_installed -eq 1 ] && [ $nginx_is_installed -eq 1 ]) && is_installed=1 || is_installed=0
case "$(uname -m)" in
    'amd64' | 'x86_64')
        machine='amd64'
        ;;
    'armv5tel' | 'armv6l' | 'armv7' | 'armv7l')
        machine='arm'
        ;;
    'armv8' | 'aarch64')
        machine='arm64'
        ;;
    *)
        machine=''
        ;;
esac

mem="$(free -m | sed -n 2p | awk '{print $2}')"
mem_total="$(($(free -m | sed -n 2p | awk '{print $2}')+$(free -m | tail -n 1 | awk '{print $2}')))"
[[ "$(free -b | tail -n 1 | awk '{print $2}')" -ne "0" ]] && using_swap=1 || using_swap=0
if [ $is_installed -eq 1 ] && ! grep -q "domain_list=" $nginx_config; then
    red "脚本进行了一次不向下兼容的更新"
    yellow "请选择 \"重新安装\" 来升级"
    sleep 3s
fi

#获取系统版本信息
get_system_info()
{
    local temp_release
    temp_release="$(lsb_release -i -s | tr "[:upper:]" "[:lower:]")"
    if [[ "$temp_release" =~ ubuntu ]]; then
        release="ubuntu"
    elif [[ "$temp_release" =~ centos ]]; then
        release="centos"
    elif [[ "$temp_release" =~ fedora ]]; then
        release="fedora"
    fi
    systemVersion="$(lsb_release -r -s)"
    if [ $release == "fedora" ]; then
        if version_ge "$systemVersion" 30; then
            redhat_version=8
        elif version_ge "$systemVersion" 19; then
            redhat_version=7
        elif version_ge "$systemVersion" 12; then
            redhat_version=6
        else
            redhat_version=5
        fi
    else
        redhat_version="$systemVersion"
    fi
}

#检查80端口和443端口是否被占用
check_port()
{
    green "正在检查端口占用。。。"
    local xray_status=0
    local nginx_status=0
    systemctl -q is-active xray && xray_status=1 && systemctl stop xray
    systemctl -q is-active nginx && nginx_status=1 && systemctl stop nginx
    ([ $xray_status -eq 1 ] || [ $nginx_status -eq 1 ]) && sleep 2s
    local check_list=('80' '443')
    local i
    for i in ${!check_list[@]}
    do
        if netstat -tuln | awk '{print $4}'  | awk -F : '{print $NF}' | grep -E "^[0-9]+$" | grep -wq "${check_list[$i]}"; then
            red "${check_list[$i]}端口被占用！"
            yellow "请用 lsof -i:${check_list[$i]} 命令检查"
            exit 1
        fi
    done
    [ $xray_status -eq 1 ] && systemctl start xray
    [ $nginx_status -eq 1 ] && systemctl start nginx
}

#检查Nginx是否已通过apt/dnf/yum安装
check_nginx_installed_system()
{
    if [[ ! -f /usr/lib/systemd/system/nginx.service ]] && [[ ! -f /lib/systemd/system/nginx.service ]]; then
        return 0
    fi
    red    "------------检测到Nginx已安装，并且会与此脚本冲突------------"
    yellow " 如果您不记得之前有安装过Nginx，那么可能是使用别的一键脚本时安装的"
    yellow " 建议使用纯净的系统运行此脚本"
    echo
    ! ask_if "是否尝试卸载？(y/n)" && exit 0
    $debian_package_manager -y purge nginx
    $redhat_package_manager -y remove nginx
    if [[ ! -f /usr/lib/systemd/system/nginx.service ]] && [[ ! -f /lib/systemd/system/nginx.service ]]; then
        return 0
    fi
    red "卸载失败！"
    yellow "请尝试更换系统，建议使用Ubuntu最新版系统"
    green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
    exit 1
}

#检查SELinux
check_SELinux()
{
    turn_off_selinux()
    {
        check_important_dependence_installed selinux-utils libselinux-utils
        setenforce 0
        sed -i 's/^[ \t]*SELINUX[ \t]*=[ \t]*enforcing[ \t]*$/SELINUX=disabled/g' /etc/sysconfig/selinux
        $redhat_package_manager -y remove libselinux-utils
        $debian_package_manager -y purge selinux-utils
    }
    if getenforce 2>/dev/null | grep -wqi Enforcing || grep -Eq '^[ '$'\t]*SELINUX[ '$'\t]*=[ '$'\t]*enforcing[ '$'\t]*$' /etc/sysconfig/selinux 2>/dev/null; then
        yellow "检测到SELinux已开启，脚本可能无法正常运行"
        if ask_if "尝试关闭SELinux?(y/n)"; then
            turn_off_selinux
        else
            exit 0
        fi
    fi
}

#配置sshd
check_ssh_timeout()
{
    if grep -q "#This file has been edited by Xray-TLS-Web-setup-script" /etc/ssh/sshd_config; then
        return 0
    fi
    echo -e "\\n\\n\\n"
    tyblue "------------------------------------------"
    tyblue " 安装可能需要比较长的时间(5-40分钟)"
    tyblue " 如果中途断开连接将会很麻烦"
    tyblue " 设置ssh连接超时时间将有效降低断连可能性"
    echo
    ! ask_if "是否设置ssh连接超时时间？(y/n)" && return 0
    sed -i '/^[ \t]*ClientAliveInterval[ \t]/d' /etc/ssh/sshd_config
    sed -i '/^[ \t]*ClientAliveCountMax[ \t]/d' /etc/ssh/sshd_config
    echo >> /etc/ssh/sshd_config
    echo "ClientAliveInterval 30" >> /etc/ssh/sshd_config
    echo "ClientAliveCountMax 60" >> /etc/ssh/sshd_config
    echo "#This file has been edited by Xray-TLS-Web-setup-script" >> /etc/ssh/sshd_config
    systemctl restart sshd
    green  "----------------------配置完成----------------------"
    tyblue " 请重新进行ssh连接(即重新登陆服务器)，并再次运行此脚本"
    yellow " 按回车键退出。。。。"
    read -s
    exit 0
}

#删除防火墙和阿里云盾
uninstall_firewall()
{
    green "正在删除防火墙。。。"
    ufw disable
    $debian_package_manager -y purge firewalld
    $debian_package_manager -y purge ufw
    systemctl stop firewalld
    systemctl disable firewalld
    $redhat_package_manager -y remove firewalld
    green "正在删除阿里云盾和腾讯云盾 (仅对阿里云和腾讯云服务器有效)。。。"
#阿里云盾
    if [ $release == "ubuntu" ] || [ $release == "other-debian" ]; then
        systemctl stop CmsGoAgent
        systemctl disable CmsGoAgent
        rm -rf /usr/local/cloudmonitor
        rm -rf /etc/systemd/system/CmsGoAgent.service
        systemctl daemon-reload
    else
        systemctl stop cloudmonitor
        /etc/rc.d/init.d/cloudmonitor remove
        rm -rf /usr/local/cloudmonitor
        systemctl daemon-reload
    fi

    systemctl stop aliyun
    systemctl disable aliyun
    rm -rf /etc/systemd/system/aliyun.service
    systemctl daemon-reload
    $debian_package_manager -y purge aliyun-assist
    $redhat_package_manager -y remove aliyun_assist
    rm -rf /usr/local/share/aliyun-assist
    rm -rf /usr/sbin/aliyun_installer
    rm -rf /usr/sbin/aliyun-service
    rm -rf /usr/sbin/aliyun-service.backup

    pkill -9 AliYunDun
    pkill -9 AliHids
    /etc/init.d/aegis uninstall
    rm -rf /usr/local/aegis
    rm -rf /etc/init.d/aegis
    rm -rf /etc/rc2.d/S80aegis
    rm -rf /etc/rc3.d/S80aegis
    rm -rf /etc/rc4.d/S80aegis
    rm -rf /etc/rc5.d/S80aegis
#腾讯云盾
    /usr/local/qcloud/stargate/admin/uninstall.sh
    /usr/local/qcloud/YunJing/uninst.sh
    /usr/local/qcloud/monitor/barad/admin/uninstall.sh
    systemctl daemon-reload
    systemctl stop YDService
    systemctl disable YDService
    rm -rf /lib/systemd/system/YDService.service
    systemctl daemon-reload
    sed -i 's#/usr/local/qcloud#rcvtevyy4f5d#g' /etc/rc.local
    sed -i '/rcvtevyy4f5d/d' /etc/rc.local
    rm -rf $(find /etc/udev/rules.d -iname "*qcloud*" 2>/dev/null)
    pkill -9 YDService
    pkill -9 YDLive
    pkill -9 sgagent
    pkill -9 tat_agent
    pkill -9 /usr/local/qcloud
    pkill -9 barad_agent
    rm -rf /usr/local/qcloud
    rm -rf /usr/local/yd.socket.client
    rm -rf /usr/local/yd.socket.server
    mkdir /usr/local/qcloud
    mkdir /usr/local/qcloud/action
    mkdir /usr/local/qcloud/action/login_banner.sh
    mkdir /usr/local/qcloud/action/action.sh
    if [[ "$(type -P uname)" ]] && uname -a | grep solaris >/dev/null; then
        crontab -l | sed "/qcloud/d" | crontab --
    else
        crontab -l | sed "/qcloud/d" | crontab -
    fi
}

#升级系统组件
doupdate()
{
    updateSystem()
    {
        if ! [[ "$(type -P do-release-upgrade)" ]]; then
            if ! $debian_package_manager -y --no-install-recommends install ubuntu-release-upgrader-core; then
                $debian_package_manager update
                if ! $debian_package_manager -y --no-install-recommends install ubuntu-release-upgrader-core; then
                    red    "脚本出错！"
                    yellow "按回车键继续或者Ctrl+c退出"
                    read -s
                fi
            fi
        fi
        echo -e "\\n\\n\\n"
        tyblue "------------------请选择升级系统版本--------------------"
        tyblue " 1.最新beta版(现在是21.04)(2020.11)"
        tyblue " 2.最新发行版(现在是20.10)(2020.11)"
        tyblue " 3.最新LTS版(现在是20.04)(2020.11)"
        tyblue "-------------------------版本说明-------------------------"
        tyblue " beta版：即测试版"
        tyblue " 发行版：即稳定版"
        tyblue " LTS版：长期支持版本，可以理解为超级稳定版"
        tyblue "-------------------------注意事项-------------------------"
        yellow " 1.升级过程中遇到问话/对话框，如果不明白，选择yes/y/第一个选项"
        yellow " 2.升级系统完成后将会重启，重启后，请再次运行此脚本完成剩余安装"
        yellow " 3.升级系统可能需要15分钟或更久"
        yellow " 4.有的时候不能一次性更新到所选择的版本，可能要更新多次"
        yellow " 5.升级系统后以下配置可能会恢复系统默认配置："
        yellow "     ssh端口   ssh超时时间    bbr加速(恢复到关闭状态)"
        tyblue "----------------------------------------------------------"
        green  " 您现在的系统版本是"$systemVersion""
        tyblue "----------------------------------------------------------"
        echo
        choice=""
        while [ "$choice" != "1" ] && [ "$choice" != "2" ] && [ "$choice" != "3" ]
        do
            read -p "您的选择是：" choice
        done
        if ! [[ "$(grep -i '^[ '$'\t]*port ' /etc/ssh/sshd_config | awk '{print $2}')" =~ ^("22"|)$ ]]; then
            red "检测到ssh端口号被修改"
            red "升级系统后ssh端口号可能恢复默认值(22)"
            yellow "按回车键继续。。。"
            read -s
        fi
        local i
        for ((i=0;i<2;i++))
        do
            sed -i '/^[ \t]*Prompt[ \t]*=/d' /etc/update-manager/release-upgrades
            echo 'Prompt=normal' >> /etc/update-manager/release-upgrades
            case "$choice" in
                1)
                    do-release-upgrade -d
                    do-release-upgrade -d
                    sed -i 's/Prompt=normal/Prompt=lts/' /etc/update-manager/release-upgrades
                    do-release-upgrade -d
                    do-release-upgrade -d
                    sed -i 's/Prompt=lts/Prompt=normal/' /etc/update-manager/release-upgrades
                    do-release-upgrade
                    do-release-upgrade
                    sed -i 's/Prompt=normal/Prompt=lts/' /etc/update-manager/release-upgrades
                    do-release-upgrade
                    do-release-upgrade
                    ;;
                2)
                    do-release-upgrade
                    do-release-upgrade
                    ;;
                3)
                    sed -i 's/Prompt=normal/Prompt=lts/' /etc/update-manager/release-upgrades
                    do-release-upgrade
                    do-release-upgrade
                    ;;
            esac
            if ! version_ge "$systemVersion" 20.04; then
                sed -i 's/Prompt=lts/Prompt=normal/' /etc/update-manager/release-upgrades
                do-release-upgrade
                do-release-upgrade
            fi
            $debian_package_manager update
            $debian_package_manager -y --auto-remove --purge full-upgrade
        done
    }
    while ((1))
    do
        echo -e "\\n\\n\\n"
        tyblue "-----------------------是否更新系统组件？-----------------------"
        green  " 1. 更新已安装软件，并升级系统 (Ubuntu专享)"
        green  " 2. 仅更新已安装软件"
        red    " 3. 不更新"
        if [ "$release" == "ubuntu" ] && ((mem<400)); then
            red "检测到内存过小，升级系统可能导致无法开机，请谨慎选择"
        fi
        echo
        choice=""
        while [ "$choice" != "1" ] && [ "$choice" != "2" ] && [ "$choice" != "3" ]
        do
            read -p "您的选择是：" choice
        done
        if [ "$release" == "ubuntu" ] || [ $choice -ne 1 ]; then
            break
        fi
        echo
        yellow " 更新系统仅支持Ubuntu！"
        sleep 3s
    done
    if [ $choice -eq 1 ]; then
        updateSystem
        $debian_package_manager -y --purge autoremove
        $debian_package_manager clean
    elif [ $choice -eq 2 ]; then
        tyblue "-----------------------即将开始更新-----------------------"
        yellow " 更新过程中遇到问话/对话框，如果不明白，选择yes/y/第一个选项"
        yellow " 按回车键继续。。。"
        read -s
        $redhat_package_manager -y autoremove
        $redhat_package_manager -y update
        $debian_package_manager update
        $debian_package_manager -y --auto-remove --purge full-upgrade
        $debian_package_manager -y --purge autoremove
        $debian_package_manager clean
        $redhat_package_manager -y autoremove
        $redhat_package_manager clean all
    fi
}

#安装bbr
install_bbr()
{
    #输出：latest_kernel_version 和 your_kernel_version
    get_kernel_info()
    {
        green "正在获取最新版本内核版本号。。。。(60内秒未获取成功自动跳过)"
        your_kernel_version="$(uname -r | cut -d - -f 1)"
        while [ ${your_kernel_version##*.} -eq 0 ]
        do
            your_kernel_version=${your_kernel_version%.*}
        done
        if ! timeout 60 wget -O "temp_kernel_version" "https://kernel.ubuntu.com/~kernel-ppa/mainline/"; then
            latest_kernel_version="error"
            return 1
        fi
        local kernel_list=()
        local kernel_list_temp
        kernel_list_temp=($(awk -F'\"v' '/v[0-9]/{print $2}' "temp_kernel_version" | cut -d '"' -f1 | cut -d '/' -f1 | sort -rV))
        if [ ${#kernel_list_temp[@]} -le 1 ]; then
            latest_kernel_version="error"
            return 1
        fi
        local i2=0
        local i3
        local kernel_rc=""
        local kernel_list_temp2
        while ((i2<${#kernel_list_temp[@]}))
        do
            if [[ "${kernel_list_temp[$i2]}" =~ -rc(0|[1-9][0-9]*)$ ]] && [ "$kernel_rc" == "" ]; then
                kernel_list_temp2=("${kernel_list_temp[$i2]}")
                kernel_rc="${kernel_list_temp[$i2]%-*}"
                ((i2++))
            elif [[ "${kernel_list_temp[$i2]}" =~ -rc(0|[1-9][0-9]*)$ ]] && [ "${kernel_list_temp[$i2]%-*}" == "$kernel_rc" ]; then
                kernel_list_temp2+=("${kernel_list_temp[$i2]}")
                ((i2++))
            elif [[ "${kernel_list_temp[$i2]}" =~ -rc(0|[1-9][0-9]*)$ ]] && [ "${kernel_list_temp[$i2]%-*}" != "$kernel_rc" ]; then
                for((i3=0;i3<${#kernel_list_temp2[@]};i3++))
                do
                    kernel_list+=("${kernel_list_temp2[$i3]}")
                done
                kernel_rc=""
            elif [ -z "$kernel_rc" ] || version_ge "${kernel_list_temp[$i2]}" "$kernel_rc"; then
                kernel_list+=("${kernel_list_temp[$i2]}")
                ((i2++))
            else
                for((i3=0;i3<${#kernel_list_temp2[@]};i3++))
                do
                    kernel_list+=("${kernel_list_temp2[$i3]}")
                done
                kernel_rc=""
            fi
        done
        if [ -n "$kernel_rc" ]; then
            for((i3=0;i3<${#kernel_list_temp2[@]};i3++))
            do
                kernel_list+=("${kernel_list_temp2[$i3]}")
            done
        fi
        latest_kernel_version="${kernel_list[0]}"
        if [ $release == "ubuntu" ] || [ $release == "other-debian" ]; then
            local rc_version
            rc_version="$(uname -r | cut -d - -f 2)"
            if [[ $rc_version =~ rc ]]; then
                rc_version="${rc_version##*'rc'}"
                your_kernel_version="${your_kernel_version}-rc${rc_version}"
            fi
            uname -r | grep -q xanmod && your_kernel_version="${your_kernel_version}-xanmod"
        else
            latest_kernel_version="${latest_kernel_version%%-*}"
        fi
    }
    #卸载多余内核
    remove_other_kernel()
    {
        if [ $release == "ubuntu" ] || [ $release == "other-debian" ]; then
            local kernel_list_image
            kernel_list_image=($(dpkg --list | awk '{print $2}' | grep '^linux-image'))
            local kernel_list_modules
            kernel_list_modules=($(dpkg --list | awk '{print $2}' | grep '^linux-modules'))
            local kernel_now
            kernel_now="$(uname -r)"
            local ok_install=0
            for ((i=${#kernel_list_image[@]}-1;i>=0;i--))
            do
                if [[ "${kernel_list_image[$i]}" =~ "$kernel_now" ]]; then
                    unset 'kernel_list_image[$i]'
                    ((ok_install++))
                fi
            done
            if [ $ok_install -lt 1 ]; then
                red "未发现正在使用的内核，可能已经被卸载，请先重新启动"
                yellow "按回车键继续。。。"
                read -s
                return 1
            fi
            for ((i=${#kernel_list_modules[@]}-1;i>=0;i--))
            do
                if [[ "${kernel_list_modules[$i]}" =~ "$kernel_now" ]]; then
                    unset 'kernel_list_modules[$i]'
                fi
            done
            if [ ${#kernel_list_modules[@]} -eq 0 ] && [ ${#kernel_list_image[@]} -eq 0 ]; then
                yellow "没有内核可卸载"
                return 0
            fi
            $debian_package_manager -y purge "${kernel_list_image[@]}" "${kernel_list_modules[@]}"
            apt-mark manual "^grub"
        else
            local kernel_list
            kernel_list=($(rpm -qa |grep '^kernel-[0-9]\|^kernel-ml-[0-9]'))
            local kernel_list_devel
            kernel_list_devel=($(rpm -qa | grep '^kernel-devel\|^kernel-ml-devel'))
            if version_ge "$redhat_version" 8; then
                local kernel_list_modules
                kernel_list_modules=($(rpm -qa |grep '^kernel-modules\|^kernel-ml-modules'))
                local kernel_list_core
                kernel_list_core=($(rpm -qa | grep '^kernel-core\|^kernel-ml-core'))
            fi
            local kernel_now
            kernel_now="$(uname -r)"
            local ok_install=0
            for ((i=${#kernel_list[@]}-1;i>=0;i--))
            do
                if [[ "${kernel_list[$i]}" =~ "$kernel_now" ]]; then
                    unset 'kernel_list[$i]'
                    ((ok_install++))
                fi
            done
            if [ $ok_install -lt 1 ]; then
                red "未发现正在使用的内核，可能已经被卸载，请先重新启动"
                yellow "按回车键继续。。。"
                read -s
                return 1
            fi
            for ((i=${#kernel_list_devel[@]}-1;i>=0;i--))
            do
                if [[ "${kernel_list_devel[$i]}" =~ "$kernel_now" ]]; then
                    unset 'kernel_list_devel[$i]'
                fi
            done
            if version_ge "$redhat_version" 8; then
                ok_install=0
                for ((i=${#kernel_list_modules[@]}-1;i>=0;i--))
                do
                    if [[ "${kernel_list_modules[$i]}" =~ "$kernel_now" ]]; then
                        unset 'kernel_list_modules[$i]'
                        ((ok_install++))
                    fi
                done
                if [ $ok_install -lt 1 ]; then
                    red "未发现正在使用的内核，可能已经被卸载，请先重新启动"
                    yellow "按回车键继续。。。"
                    read -s
                    return 1
                fi
                ok_install=0
                for ((i=${#kernel_list_core[@]}-1;i>=0;i--))
                do
                    if [[ "${kernel_list_core[$i]}" =~ "$kernel_now" ]]; then
                        unset 'kernel_list_core[$i]'
                        ((ok_install++))
                    fi
                done
                if [ $ok_install -lt 1 ]; then
                    red "未发现正在使用的内核，可能已经被卸载，请先重新启动"
                    yellow "按回车键继续。。。"
                    read -s
                    return 1
                fi
            fi
            if ([ ${#kernel_list[@]} -eq 0 ] && [ ${#kernel_list_devel[@]} -eq 0 ]) && (! version_ge "$redhat_version" 8 || ([ ${#kernel_list_modules[@]} -eq 0 ] && [ ${#kernel_list_core[@]} -eq 0 ])); then
                yellow "没有内核可卸载"
                return 0
            fi
            if version_ge "$redhat_version" 8; then
                $redhat_package_manager -y remove "${kernel_list[@]}" "${kernel_list_modules[@]}" "${kernel_list_core[@]}" "${kernel_list_devel[@]}"
            else
                $redhat_package_manager -y remove "${kernel_list[@]}" "${kernel_list_devel[@]}"
            fi
        fi
        green "-------------------卸载完成-------------------"
    }
    change_qdisc()
    {
        local list=('fq' 'fq_pie' 'cake' 'fq_codel')
        tyblue "---------------请选择你要使用的队列算法---------------"
        green  " 1.fq"
        green  " 2.fq_pie"
        tyblue " 3.cake"
        tyblue " 4.fq_codel"
        choice=""
        while [[ ! "$choice" =~ ^([1-9][0-9]*)$ ]] || ((choice>4))
        do
            read -p "您的选择是：" choice
        done
        local qdisc="${list[$((choice-1))]}"
        local default_qdisc
        default_qdisc="$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')"
        sed -i '/^[ \t]*net.core.default_qdisc[ \t]*=/d' /etc/sysctl.conf
        echo "net.core.default_qdisc = $qdisc" >> /etc/sysctl.conf
        sysctl -p
        sleep 1s
        if [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "$qdisc" ]; then
            green "更换成功！"
        else
            red "更换失败，内核不支持"
            sed -i '/^[ \t]*net.core.default_qdisc[ \t]*=/d' /etc/sysctl.conf
            echo "net.core.default_qdisc = $default_qdisc" >> /etc/sysctl.conf
            return 1
        fi
    }
    local your_kernel_version
    local latest_kernel_version
    get_kernel_info
    if ! grep -q "#This file has been edited by Xray-TLS-Web-setup-script" /etc/sysctl.conf; then
        echo >> /etc/sysctl.conf
        echo "#This file has been edited by Xray-TLS-Web-setup-script" >> /etc/sysctl.conf
    fi
    while ((1))
    do
        echo -e "\\n\\n\\n"
        tyblue "------------------请选择要使用的bbr版本------------------"
        green  " 1. 升级最新版内核并启用bbr(推荐)"
        green  " 2. 安装xanmod内核并启用bbr(推荐)"
        if version_ge $your_kernel_version 4.9; then
            tyblue " 3. 启用bbr"
        else
            tyblue " 3. 升级内核启用bbr"
        fi
        tyblue " 4. 安装第三方内核并启用bbr2"
        tyblue " 5. 安装第三方内核并启用bbrplus/bbr魔改版/暴力bbr魔改版/锐速"
        tyblue " 6. 卸载多余内核"
        tyblue " 7. 更换队列算法"
        tyblue " 0. 退出bbr安装"
        tyblue "------------------关于安装bbr加速的说明------------------"
        green  " bbr拥塞算法可以大幅提升网络速度，建议启用"
        yellow " 更换第三方内核可能造成系统不稳定，甚至无法开机"
        yellow " 更换/升级内核需重启，重启后，请再次运行此脚本完成剩余安装"
        tyblue "---------------------------------------------------------"
        tyblue " 当前内核版本：${your_kernel_version}"
        tyblue " 最新内核版本：${latest_kernel_version}"
        tyblue " 当前内核是否支持bbr："
        if version_ge $your_kernel_version 4.9; then
            green "     是"
        else
            red "     否，需升级内核"
        fi
        tyblue "   当前拥塞控制算法："
        local tcp_congestion_control
        tcp_congestion_control=$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')
        if [[ "$tcp_congestion_control" =~ bbr|nanqinlang|tsunami ]]; then
            if [ $tcp_congestion_control == nanqinlang ]; then
                tcp_congestion_control="${tcp_congestion_control} \\033[35m(暴力bbr魔改版)"
            elif [ $tcp_congestion_control == tsunami ]; then
                tcp_congestion_control="${tcp_congestion_control} \\033[35m(bbr魔改版)"
            fi
            green  "       ${tcp_congestion_control}"
        else
            tyblue "       ${tcp_congestion_control} \\033[31m(bbr未启用)"
        fi
        tyblue "   当前队列算法："
        green "       $(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')"
        echo
        local choice=""
        while [[ ! "$choice" =~ ^(0|[1-9][0-9]*)$ ]] || ((choice>7))
        do
            read -p "您的选择是：" choice
        done
        if [ $choice -eq 1 ]; then
            if ! ([ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(grep '^[ '$'\t]*net.ipv4.tcp_congestion_control[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "$(grep '^[ '$'\t]*net.core.default_qdisc[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" ]); then
                sed -i '/^[ \t]*net.core.default_qdisc[ \t]*=/d' /etc/sysctl.conf
                sed -i '/^[ \t]*net.ipv4.tcp_congestion_control[ \t]*=/d' /etc/sysctl.conf
                echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
                echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
                sysctl -p
            fi
            if ! wget -O update-kernel.sh https://github.com/kirin10000/update-kernel/raw/master/update-kernel.sh; then
                red    "获取内核升级脚本失败"
                yellow "按回车键继续或者按Ctrl+c终止"
                read -s
            fi
            chmod +x update-kernel.sh
            ./update-kernel.sh
            if [ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "$(grep '^[ '$'\t]*net.core.default_qdisc[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" ]; then
                green "--------------------bbr已安装--------------------"
            else
                red "开启bbr失败"
                red "如果刚安装完内核，请先重启"
                red "如果重启仍然无效，请尝试选项3"
            fi
        elif [ $choice -eq 2 ]; then
            if ! ([ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(grep '^[ '$'\t]*net.ipv4.tcp_congestion_control[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "$(grep '^[ '$'\t]*net.core.default_qdisc[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" ]); then
                sed -i '/^[ \t]*net.core.default_qdisc[ \t]*=/d' /etc/sysctl.conf
                sed -i '/^[ \t]*net.ipv4.tcp_congestion_control[ \t]*=/d' /etc/sysctl.conf
                echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
                echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
                sysctl -p
            fi
            if ! wget -O xanmod-install.sh https://github.com/kirin10000/xanmod-install/raw/main/xanmod-install.sh; then
                red    "获取xanmod内核安装脚本失败"
                yellow "按回车键继续或者按Ctrl+c终止"
                read -s
            fi
            chmod +x xanmod-install.sh
            ./xanmod-install.sh
            if [ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "$(grep '^[ '$'\t]*net.core.default_qdisc[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" ]; then
                green "--------------------bbr已安装--------------------"
            else
                red "开启bbr失败"
                red "如果刚安装完内核，请先重启"
                red "如果重启仍然无效，请尝试选项3"
            fi
        elif [ $choice -eq 3 ]; then
            if [ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(grep '^[ '$'\t]*net.ipv4.tcp_congestion_control[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "$(grep '^[ '$'\t]*net.core.default_qdisc[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" ]; then
                green "--------------------bbr已安装--------------------"
            else
                sed -i '/^[ \t]*net.core.default_qdisc[ \t]*=/d' /etc/sysctl.conf
                sed -i '/^[ \t]*net.ipv4.tcp_congestion_control[ \t]*=/d' /etc/sysctl.conf
                echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
                echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
                sysctl -p
                sleep 1s
                if [ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "fq" ]; then
                    green "--------------------bbr已安装--------------------"
                else
                    if ! wget -O bbr.sh https://github.com/teddysun/across/raw/master/bbr.sh; then
                        red    "获取bbr脚本失败"
                        yellow "按回车键继续或者按Ctrl+c终止"
                        read -s
                    fi
                    chmod +x bbr.sh
                    ./bbr.sh
                fi
            fi
        elif [ $choice -eq 4 ]; then
            tyblue "--------------------即将安装bbr2加速，安装完成后服务器将会重启--------------------"
            tyblue " 重启后，请再次选择这个选项完成bbr2剩余部分安装(开启bbr和ECN)"
            yellow " 按回车键以继续。。。。"
            read -s
            local temp_bbr2
            if [ $release == "ubuntu" ] || [ $release == "other-debian" ]; then
                local temp_bbr2="https://github.com/yeyingorg/bbr2.sh/raw/master/bbr2.sh"
            else
                local temp_bbr2="https://github.com/jackjieYYY/bbr2/raw/master/bbr2.sh"
            fi
            if ! wget -O bbr2.sh $temp_bbr2; then
                red    "获取bbr2脚本失败"
                yellow "按回车键继续或者按Ctrl+c终止"
                read -s
            fi
            chmod +x bbr2.sh
            ./bbr2.sh
        elif [ $choice -eq 5 ]; then
            if ! wget -O tcp.sh "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh"; then
                red    "获取脚本失败"
                yellow "按回车键继续或者按Ctrl+c终止"
                read -s
            fi
            chmod +x tcp.sh
            ./tcp.sh
        elif [ $choice -eq 6 ]; then
            tyblue " 该操作将会卸载除现在正在使用的内核外的其余内核"
            tyblue "    您正在使用的内核是：$(uname -r)"
            ask_if "是否继续？(y/n)" && remove_other_kernel
        elif [ $choice -eq 7 ]; then
            change_qdisc
        else
            break
        fi
        sleep 3s
    done
}

#读取xray_protocol配置
readProtocolConfig()
{
    echo -e "\\n\\n\\n"
    tyblue "---------------------请选择Xray要使用协议---------------------"
    tyblue " 1. (VLESS-TCP+XTLS) + (VMess-WebSocket+TLS) + Web"
    green  "    适合有时使用CDN，且CDN不可信任(如国内CDN)"
    tyblue " 2. (VLESS-TCP+XTLS) + (VLESS-WebSocket+TLS) + Web"
    green  "    适合有时使用CDN，且CDN可信任"
    tyblue " 3. VLESS-TCP+XTLS+Web"
    green  "    适合完全不用CDN"
    tyblue " 4. VMess-WebSocket+TLS+Web"
    green  "    适合一直使用CDN，且CDN不可信任(如国内CDN)"
    tyblue " 5. VLESS-WebSocket+TLS+Web"
    green  "    适合一直使用CDN，且CDN可信任"
    echo
    yellow " 注："
    yellow "   1.各协议理论速度对比：github.com/badO1a5A90/v2ray-doc/blob/main/Xray_test_v1.1.1.md"
    yellow "   2.XTLS完全兼容TLS"
    yellow "   3.WebSocket协议支持CDN，TCP不支持"
    yellow "   4.VLESS协议用于CDN，CDN可以看见传输的明文"
    yellow "   5.若不知CDN为何物，请选3"
    echo
    local mode=""
    while [[ "$mode" != "1" && "$mode" != "2" && "$mode" != "3" && "$mode" != "4" && "$mode" != "5" ]]
    do
        read -p "您的选择是：" mode
    done
    if [ $mode -eq 1 ]; then
        protocol_1=1
        protocol_2=2
    elif [ $mode -eq 2 ]; then
        protocol_1=1
        protocol_2=1
    elif [ $mode -eq 3 ]; then
        protocol_1=1
        protocol_2=0
    elif [ $mode -eq 4 ]; then
        protocol_1=0
        protocol_2=2
    elif [ $mode -eq 5 ]; then
        protocol_1=0
        protocol_2=1
    fi
}

#读取伪装类型 输出pretend
readPretend()
{
    local queren=0
    while [ $queren -ne 1 ]
    do
        echo -e "\\n\\n\\n"
        tyblue "------------------------------请选择要伪装的网站页面------------------------------"
        tyblue " 1. Cloudreve \\033[32m(推荐)"
        purple "     个人网盘"
        tyblue " 2. Nextcloud \\033[32m(推荐)"
        purple "     个人网盘，需安装php"
        tyblue " 3. 403页面"
        purple "     模拟网站后台"
        tyblue " 4. 自定义静态网站"
        purple "     不建议小白选择，默认为Nextcloud登陆界面，强烈建议自行更换"
        tyblue " 5. 自定义反向代理网页 \033[31m(不推荐)"
        echo
        green  " 内存<128MB 建议选择 403页面"
        green  " 128MB<=内存<1G 建议选择 Cloudreve"
        green  " 内存>=1G 建议选择 Nextcloud 或 Cloudreve"
        echo
        yellow " 关于选择伪装网站的详细说明见：https://github.com/kirin10000/Xray-script#伪装网站说明"
        echo
        pretend=""
        while [[ "$pretend" != "1" && "$pretend" != "2" && "$pretend" != "3" && "$pretend" != "4" && "$pretend" != "5" ]]
        do
            read -p "您的选择是：" pretend
        done
        queren=1
        if [ $pretend -eq 1 ]; then
            if [ -z "$machine" ]; then
                red "您的VPS指令集不支持Cloudreve！"
                sleep 3s
                queren=0
            fi
        elif [ $pretend -eq 2 ]; then
            if ([ $release == "centos" ] || [ $release == "fedora" ] || [ $release == "other-redhat" ]) && ! version_ge "$redhat_version" 8; then
                red "不支持在 Red Hat版本<8 的 Red Hat基 系统上安装php"
                yellow "如：CentOS<8 Fedora<30 的版本"
                sleep 3s
                queren=0
            elif [ $php_is_installed -eq 0 ]; then
                tyblue "安装Nextcloud需要安装php"
                yellow "编译&&安装php可能需要额外消耗15-60分钟"
                yellow "php将占用一定系统资源，不建议内存<512M的机器使用"
                ! ask_if "确定选择吗？(y/n)" && queren=0
            fi
        elif [ $pretend -eq 5 ]; then
            yellow "输入反向代理网址，格式如：\"https://v.qq.com\""
            pretend=""
            while [ -z "$pretend" ]
            do
                read -p "请输入反向代理网址：" pretend
            done
        fi
    done
}
readDomain()
{
    check_domain()
    {
        if [ -z "$1" ]; then
            return 1
        elif [ "${1%%.*}" == "www" ]; then
            red "域名前面不要带www！"
            return 1
        else
            return 0
        fi
    }
    local domain
    local domain_config=""
    local pretend
    echo -e "\\n\\n\\n"
    tyblue "--------------------请选择域名解析情况--------------------"
    tyblue " 1. 一级域名 和 www.一级域名 都解析到此服务器上 \\033[32m(推荐)"
    green  "    如：123.com 和 www.123.com 都解析到此服务器上"
    tyblue " 2. 仅某个域名解析到此服务器上"
    green  "    如：123.com 或 www.123.com 或 xxx.123.com 中的某一个解析到此服务器上"
    echo
    while [ "$domain_config" != "1" ] && [ "$domain_config" != "2" ]
    do
        read -p "您的选择是：" domain_config
    done
    local queren=0
    while [ $queren -ne 1 ]
    do
        domain=""
        echo
        if [ $domain_config -eq 1 ]; then
            tyblue '---------请输入一级域名(前面不带"www."、"http://"或"https://")---------'
            while ! check_domain "$domain"
            do
                read -p "请输入域名：" domain
            done
        else
            tyblue '-------请输入解析到此服务器的域名(前面不带"http://"或"https://")-------'
            while [ -z "$domain" ]
            do
                read -p "请输入域名：" domain
            done
        fi
        echo
        ask_if "您输入的域名是\"$domain\"，确认吗？(y/n)" && queren=1
    done
    readPretend
    true_domain_list+=("$domain")
    [ $domain_config -eq 1 ] && domain_list+=("www.$domain") || domain_list+=("$domain")
    domain_config_list+=("$domain_config")
    pretend_list+=("$pretend")
}

#安装依赖
install_base_dependence()
{
    if [ $release == "centos" ] || [ $release == "fedora" ] || [ $release == "other-redhat" ]; then
        install_dependence net-tools redhat-lsb-core ca-certificates wget unzip curl openssl crontabs gcc gcc-c++ make
    else
        install_dependence net-tools lsb-release ca-certificates wget unzip curl openssl cron gcc g++ make
    fi
}
install_nginx_dependence()
{
    if [ $release == "centos" ] || [ $release == "fedora" ] || [ $release == "other-redhat" ]; then
        install_dependence perl-IPC-Cmd perl-Getopt-Long perl-Data-Dumper pcre-devel zlib-devel libxml2-devel libxslt-devel gd-devel geoip-devel perl-ExtUtils-Embed gperftools-devel libatomic_ops-devel perl-devel
    else
        install_dependence libpcre3-dev zlib1g-dev libxml2-dev libxslt1-dev libgd-dev libgeoip-dev libgoogle-perftools-dev libatomic-ops-dev libperl-dev
    fi
}
install_php_dependence()
{
    if [ $release == "centos" ] || [ $release == "fedora" ] || [ $release == "other-redhat" ]; then
        install_dependence pkgconf-pkg-config libxml2-devel sqlite-devel systemd-devel libacl-devel openssl-devel krb5-devel pcre2-devel zlib-devel bzip2-devel libcurl-devel gdbm-devel libdb-devel tokyocabinet-devel lmdb-devel enchant-devel libffi-devel libpng-devel gd-devel libwebp-devel libjpeg-turbo-devel libXpm-devel freetype-devel gmp-devel libc-client-devel libicu-devel openldap-devel oniguruma-devel unixODBC-devel freetds-devel libpq-devel aspell-devel libedit-devel net-snmp-devel libsodium-devel libargon2-devel libtidy-devel libxslt-devel libzip-devel autoconf git ImageMagick-devel
    else
        install_dependence pkg-config libxml2-dev libsqlite3-dev libsystemd-dev libacl1-dev libapparmor-dev libssl-dev libkrb5-dev libpcre2-dev zlib1g-dev libbz2-dev libcurl4-openssl-dev libqdbm-dev libdb-dev libtokyocabinet-dev liblmdb-dev libenchant-dev libffi-dev libpng-dev libgd-dev libwebp-dev libjpeg-dev libxpm-dev libfreetype6-dev libgmp-dev libc-client2007e-dev libicu-dev libldap2-dev libsasl2-dev libonig-dev unixodbc-dev freetds-dev libpq-dev libpspell-dev libedit-dev libmm-dev libsnmp-dev libsodium-dev libargon2-dev libtidy-dev libxslt1-dev libzip-dev autoconf git libmagickwand-dev
    fi
}

#编译&&安装php
compile_php()
{
    green "正在编译php。。。。"
    if ! wget -O "${php_version}.tar.xz" "https://www.php.net/distributions/${php_version}.tar.xz"; then
        red    "获取php失败"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    fi
    tar -xJf "${php_version}.tar.xz"
    cd "${php_version}"
    sed -i 's#db$THIS_VERSION/db_185.h include/db$THIS_VERSION/db_185.h include/db/db_185.h#& include/db_185.h#' configure
    if [ $release == "ubuntu" ] || [ $release == "other-debian" ]; then
        sed -i 's#if test -f $THIS_PREFIX/$PHP_LIBDIR/lib$LIB\.a || test -f $THIS_PREFIX/$PHP_LIBDIR/lib$LIB\.$SHLIB_SUFFIX_NAME#& || true#' configure
        sed -i 's#if test ! -r "$PDO_FREETDS_INSTALLATION_DIR/$PHP_LIBDIR/libsybdb\.a" && test ! -r "$PDO_FREETDS_INSTALLATION_DIR/$PHP_LIBDIR/libsybdb\.so"#& \&\& false#' configure
        ./configure --prefix=${php_prefix} --enable-embed=shared --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --with-fpm-systemd --with-fpm-acl --with-fpm-apparmor --disable-phpdbg --with-layout=GNU --with-openssl --with-kerberos --with-external-pcre --with-pcre-jit --with-zlib --enable-bcmath --with-bz2 --enable-calendar --with-curl --enable-dba --with-qdbm --with-db4 --with-db1 --with-tcadb --with-lmdb --with-enchant --enable-exif --with-ffi --enable-ftp --enable-gd --with-external-gd --with-webp --with-jpeg --with-xpm --with-freetype --enable-gd-jis-conv --with-gettext --with-gmp --with-mhash --with-imap --with-imap-ssl --enable-intl --with-ldap --with-ldap-sasl --enable-mbstring --with-mysqli --with-mysql-sock --with-unixODBC --enable-pcntl --with-pdo-dblib --with-pdo-mysql --with-zlib-dir --with-pdo-odbc=unixODBC,/usr --with-pdo-pgsql --with-pgsql --with-pspell --with-libedit --with-mm --enable-shmop --with-snmp --enable-soap --enable-sockets --with-sodium --with-password-argon2 --enable-sysvmsg --enable-sysvsem --enable-sysvshm --with-tidy --with-xsl --with-zip --enable-mysqlnd --with-pear CPPFLAGS="-g0 -O3" CFLAGS="-g0 -O3" CXXFLAGS="-g0 -O3"
    else
        ./configure --prefix=${php_prefix} --with-libdir=lib64 --enable-embed=shared --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --with-fpm-systemd --with-fpm-acl --disable-phpdbg --with-layout=GNU --with-openssl --with-kerberos --with-external-pcre --with-pcre-jit --with-zlib --enable-bcmath --with-bz2 --enable-calendar --with-curl --enable-dba --with-gdbm --with-db4 --with-db1 --with-tcadb --with-lmdb --with-enchant --enable-exif --with-ffi --enable-ftp --enable-gd --with-external-gd --with-webp --with-jpeg --with-xpm --with-freetype --enable-gd-jis-conv --with-gettext --with-gmp --with-mhash --with-imap --with-imap-ssl --enable-intl --with-ldap --with-ldap-sasl --enable-mbstring --with-mysqli --with-mysql-sock --with-unixODBC --enable-pcntl --with-pdo-dblib --with-pdo-mysql --with-zlib-dir --with-pdo-odbc=unixODBC,/usr --with-pdo-pgsql --with-pgsql --with-pspell --with-libedit --enable-shmop --with-snmp --enable-soap --enable-sockets --with-sodium --with-password-argon2 --enable-sysvmsg --enable-sysvsem --enable-sysvshm --with-tidy --with-xsl --with-zip --enable-mysqlnd --with-pear CPPFLAGS="-g0 -O3" CFLAGS="-g0 -O3" CXXFLAGS="-g0 -O3"
    fi
    swap_on 1800
    if ! make; then
        swap_off
        red    "php编译失败！"
        green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
        yellow "在Bug修复前，建议使用Ubuntu最新版系统"
        exit 1
    fi
    swap_off
    cd ..
}
install_php_part1()
{
    green "正在安装php。。。。"
    cd "${php_version}"
    make install
    cp sapi/fpm/php-fpm.service ${php_prefix}/php-fpm.service.default
    cd ..
    php_is_installed=1
}
instal_php_imagick()
{
    if ! git clone https://github.com/Imagick/imagick; then
        yellow "获取php-imagick源码失败"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    fi
    cd imagick
    ${php_prefix}/bin/phpize
    ./configure --with-php-config=${php_prefix}/bin/php-config CFLAGS="-g0 -O3"
    swap_on 380
    if ! make; then
        swap_off
        yellow "php-imagick编译失败"
        green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
        yellow "在Bug修复前，建议使用Ubuntu最新版系统"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    else
        swap_off
    fi
    mv modules/imagick.so "$(${php_prefix}/bin/php -i | grep "^extension_dir" | awk '{print $3}')"
    cd ..
}
install_php_part2()
{
    useradd -r -s /bin/bash www-data
    cp ${php_prefix}/etc/php-fpm.conf.default ${php_prefix}/etc/php-fpm.conf
    cp ${php_prefix}/etc/php-fpm.d/www.conf.default ${php_prefix}/etc/php-fpm.d/www.conf
    sed -i '/^[ \t]*listen[ \t]*=/d' ${php_prefix}/etc/php-fpm.d/www.conf
    echo "listen = /dev/shm/php-fpm_unixsocket/php.sock" >> ${php_prefix}/etc/php-fpm.d/www.conf
    sed -i '/^[ \t]*env\[PATH\][ \t]*=/d' ${php_prefix}/etc/php-fpm.d/www.conf
    echo "env[PATH] = $PATH" >> ${php_prefix}/etc/php-fpm.d/www.conf
    instal_php_imagick
cat > ${php_prefix}/etc/php.ini << EOF
[PHP]
memory_limit=-1
upload_max_filesize=-1
extension=imagick.so
zend_extension=opcache.so
opcache.enable=1
EOF
    install -m 644 "${php_prefix}/php-fpm.service.default" $php_service
cat >> $php_service <<EOF

[Service]
ProtectSystem=false
ExecStartPre=/bin/rm -rf /dev/shm/php-fpm_unixsocket
ExecStartPre=/bin/mkdir /dev/shm/php-fpm_unixsocket
ExecStartPre=/bin/chmod 711 /dev/shm/php-fpm_unixsocket
ExecStopPost=/bin/rm -rf /dev/shm/php-fpm_unixsocket
EOF
    systemctl daemon-reload
}

#编译&&安装nignx
compile_nginx()
{
    green "正在编译Nginx。。。。"
    if ! wget -O ${nginx_version}.tar.gz https://nginx.org/download/${nginx_version}.tar.gz; then
        red    "获取nginx失败"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    fi
    tar -zxf ${nginx_version}.tar.gz
    if ! wget -O ${openssl_version}.tar.gz https://github.com/openssl/openssl/archive/${openssl_version#*-}.tar.gz; then
        red    "获取openssl失败"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    fi
    tar -zxf ${openssl_version}.tar.gz
    cd ${nginx_version}
    sed -i "s/OPTIMIZE[ \\t]*=>[ \\t]*'-O'/OPTIMIZE          => '-O3'/g" src/http/modules/perl/Makefile.PL
    ./configure --prefix=/usr/local/nginx --with-openssl=../$openssl_version --with-mail=dynamic --with-mail_ssl_module --with-stream=dynamic --with-stream_ssl_module --with-stream_realip_module --with-stream_geoip_module=dynamic --with-stream_ssl_preread_module --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_addition_module --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_auth_request_module --with-http_random_index_module --with-http_secure_link_module --with-http_degradation_module --with-http_slice_module --with-http_stub_status_module --with-http_perl_module=dynamic --with-pcre --with-libatomic --with-compat --with-cpp_test_module --with-google_perftools_module --with-file-aio --with-threads --with-poll_module --with-select_module --with-cc-opt="-Wno-error -g0 -O3"
    swap_on 480
    if ! make; then
        swap_off
        red    "Nginx编译失败！"
        green  "欢迎进行Bug report(https://github.com/kirin10000/Xray-script/issues)，感谢您的支持"
        yellow "在Bug修复前，建议使用Ubuntu最新版系统"
        exit 1
    fi
    swap_off
    cd ..
}
config_service_nginx()
{
    rm -rf $nginx_service
cat > $nginx_service << EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
User=root
ExecStartPre=/bin/rm -rf /dev/shm/nginx_unixsocket
ExecStartPre=/bin/mkdir /dev/shm/nginx_unixsocket
ExecStartPre=/bin/chmod 711 /dev/shm/nginx_unixsocket
ExecStartPre=/bin/rm -rf /dev/shm/nginx_tcmalloc
ExecStartPre=/bin/mkdir /dev/shm/nginx_tcmalloc
ExecStartPre=/bin/chmod 0777 /dev/shm/nginx_tcmalloc
ExecStart=${nginx_prefix}/sbin/nginx
ExecStop=${nginx_prefix}/sbin/nginx -s stop
ExecStopPost=/bin/rm -rf /dev/shm/nginx_tcmalloc
ExecStopPost=/bin/rm -rf /dev/shm/nginx_unixsocket
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 $nginx_service
    systemctl daemon-reload
}
install_nginx_part1()
{
    green "正在安装Nginx。。。"
    cd ${nginx_version}
    make install
    cd ..
}
install_nginx_part2()
{
    mkdir ${nginx_prefix}/conf.d
    touch $nginx_config
    mkdir ${nginx_prefix}/certs
    mkdir ${nginx_prefix}/html/issue_certs
cat > ${nginx_prefix}/conf/issue_certs.conf << EOF
events {
    worker_connections  1024;
}
http {
    server {
        listen [::]:80 ipv6only=off;
        root ${nginx_prefix}/html/issue_certs;
    }
}
EOF
cat > ${nginx_prefix}/conf.d/nextcloud.conf <<EOF
    client_max_body_size 0;
    fastcgi_buffers 64 4K;
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
    add_header Referrer-Policy                      "no-referrer"   always;
    add_header X-Content-Type-Options               "nosniff"       always;
    add_header X-Download-Options                   "noopen"        always;
    add_header X-Frame-Options                      "SAMEORIGIN"    always;
    add_header X-Permitted-Cross-Domain-Policies    "none"          always;
    add_header X-Robots-Tag                         "none"          always;
    add_header X-XSS-Protection                     "1; mode=block" always;
    fastcgi_hide_header X-Powered-By;
    index index.php index.html /index.php\$request_uri;
    expires 1m;
    location = / {
        if ( \$http_user_agent ~ ^DavClnt ) {
            return 302 /remote.php/webdav/\$is_args\$args;
        }
    }
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
    location ~ ^/(?:\\.|autotest|occ|issue|indie|db_|console)              { return 404; }
    location ~ \\.php(?:$|/) {
        include fastcgi.conf;
        fastcgi_param REMOTE_ADDR 127.0.0.1;
        fastcgi_split_path_info ^(.+?\\.php)(/.*)$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass unix:/dev/shm/php-fpm_unixsocket/php.sock;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }
    location ~ \\.(?:css|js|svg|gif)$ {
        try_files \$uri /index.php\$request_uri;
        expires 6M;         # Cache-Control policy borrowed from \`.htaccess\`
        access_log off;     # Optional: Don't log access to assets
    }
    location ~ \\.woff2?$ {
        try_files \$uri /index.php\$request_uri;
        expires 7d;         # Cache-Control policy borrowed from \`.htaccess\`
        access_log off;     # Optional: Don't log access to assets
    }
    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }
EOF
    config_service_nginx
    systemctl enable nginx
    nginx_is_installed=1
}

#安装/更新Xray
install_update_xray()
{
    green "正在安装/更新Xray。。。。"
    if ! bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --without-geodata && ! bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --without-geodata; then
        red    "安装/更新Xray失败"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
        return 1
    fi
}

#获取证书 参数: 域名位置
get_cert()
{
    mv $xray_config ${xray_config}.bak
    mv ${nginx_prefix}/conf/nginx.conf ${nginx_prefix}/conf/nginx.conf.bak2
    cp ${nginx_prefix}/conf/nginx.conf.default ${nginx_prefix}/conf/nginx.conf
    echo "{}" > $xray_config
    local temp=""
    [ ${domain_config_list[$1]} -eq 1 ] && temp="-d ${domain_list[$1]}"
    if ! $HOME/.acme.sh/acme.sh --issue -d ${true_domain_list[$1]} $temp -w ${nginx_prefix}/html/issue_certs -k ec-256 -ak ec-256 --pre-hook "mv ${nginx_prefix}/conf/nginx.conf ${nginx_prefix}/conf/nginx.conf.bak && cp ${nginx_prefix}/conf/issue_certs.conf ${nginx_prefix}/conf/nginx.conf && sleep 2s && systemctl restart nginx" --post-hook "mv ${nginx_prefix}/conf/nginx.conf.bak ${nginx_prefix}/conf/nginx.conf && sleep 2s && systemctl restart nginx" --ocsp; then
        $HOME/.acme.sh/acme.sh --issue -d ${true_domain_list[$1]} $temp -w ${nginx_prefix}/html/issue_certs -k ec-256 -ak ec-256 --pre-hook "mv ${nginx_prefix}/conf/nginx.conf ${nginx_prefix}/conf/nginx.conf.bak && cp ${nginx_prefix}/conf/issue_certs.conf ${nginx_prefix}/conf/nginx.conf && sleep 2s && systemctl restart nginx" --post-hook "mv ${nginx_prefix}/conf/nginx.conf.bak ${nginx_prefix}/conf/nginx.conf && sleep 2s && systemctl restart nginx" --ocsp --debug
    fi
    if ! $HOME/.acme.sh/acme.sh --installcert -d ${true_domain_list[$1]} --key-file ${nginx_prefix}/certs/${true_domain_list[$1]}.key --fullchain-file ${nginx_prefix}/certs/${true_domain_list[$1]}.cer --reloadcmd "sleep 2s && systemctl restart xray" --ecc; then
        $HOME/.acme.sh/acme.sh --remove --domain ${true_domain_list[$1]} --ecc
        rm -rf $HOME/.acme.sh/${true_domain_list[$1]}_ecc
        rm -rf "${nginx_prefix}/certs/${true_domain_list[$1]}.key" "${nginx_prefix}/certs/${true_domain_list[$1]}.cer"
        mv ${xray_config}.bak $xray_config
        mv ${nginx_prefix}/conf/nginx.conf.bak2 ${nginx_prefix}/conf/nginx.conf
        return 1
    fi
    mv ${xray_config}.bak $xray_config
    mv ${nginx_prefix}/conf/nginx.conf.bak2 ${nginx_prefix}/conf/nginx.conf
    return 0
}
get_all_certs()
{
    local i
    for ((i=0;i<${#domain_list[@]};i++))
    do
        if ! get_cert "$i"; then
            red    "域名\"${true_domain_list[$i]}\"证书申请失败！"
            yellow "请检查："
            yellow "    1.域名是否解析正确"
            yellow "    2.vps防火墙80端口是否开放"
            yellow "并在安装/重置域名完成后，使用脚本主菜单\"重置域名\"选项修复"
            yellow "按回车键继续。。。"
            read -s
        fi
    done
}

#配置nginx
config_nginx_init()
{
cat > ${nginx_prefix}/conf/nginx.conf <<EOF

user  root root;
worker_processes  auto;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;
google_perftools_profiles /dev/shm/nginx_tcmalloc/tcmalloc;

events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
    #                  '\$status \$body_bytes_sent "\$http_referer" '
    #                  '"\$http_user_agent" "\$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    #gzip  on;

    include       $nginx_config;
    #server {
        #listen       80;
        #server_name  localhost;

        #charset koi8-r;

        #access_log  logs/host.access.log  main;

        #location / {
        #    root   html;
        #    index  index.html index.htm;
        #}

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        #error_page   500 502 503 504  /50x.html;
        #location = /50x.html {
        #    root   html;
        #}

        # proxy the PHP scripts to Apache listening on 127.0.0.1:80
        #
        #location ~ \\.php\$ {
        #    proxy_pass   http://127.0.0.1;
        #}

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
        #
        #location ~ \\.php\$ {
        #    root           html;
        #    fastcgi_pass   127.0.0.1:9000;
        #    fastcgi_index  index.php;
        #    fastcgi_param  SCRIPT_FILENAME  /scripts\$fastcgi_script_name;
        #    include        fastcgi_params;
        #}

        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\\.ht {
        #    deny  all;
        #}
    #}


    # another virtual host using mix of IP-, name-, and port-based configuration
    #
    #server {
    #    listen       8000;
    #    listen       somename:8080;
    #    server_name  somename  alias  another.alias;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}


    # HTTPS server
    #
    #server {
    #    listen       443 ssl;
    #    server_name  localhost;

    #    ssl_certificate      cert.pem;
    #    ssl_certificate_key  cert.key;

    #    ssl_session_cache    shared:SSL:1m;
    #    ssl_session_timeout  5m;

    #    ssl_ciphers  HIGH:!aNULL:!MD5;
    #    ssl_prefer_server_ciphers  on;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}

}
EOF
}
config_nginx()
{
    config_nginx_init
    local i
cat > $nginx_config<<EOF
server {
    listen 80 reuseport default_server;
    listen [::]:80 reuseport default_server;
    return 301 https://${domain_list[0]};
}
server {
    listen 80;
    listen [::]:80;
    server_name ${domain_list[@]};
    return 301 https://\$host\$request_uri;
}
EOF
    local temp_domain_list2=()
    for i in ${!domain_config_list[@]}
    do
        [ ${domain_config_list[$i]} -eq 1 ] && temp_domain_list2+=("${true_domain_list[$i]}")
    done
    if [ ${#temp_domain_list2[@]} -ne 0 ]; then
cat >> $nginx_config<<EOF
server {
    listen 80;
    listen [::]:80;
    listen unix:/dev/shm/nginx_unixsocket/default.sock;
    listen unix:/dev/shm/nginx_unixsocket/h2.sock http2;
    server_name ${temp_domain_list2[@]};
    return 301 https://www.\$host\$request_uri;
}
EOF
    fi
cat >> $nginx_config<<EOF
server {
    listen unix:/dev/shm/nginx_unixsocket/default.sock default_server;
    listen unix:/dev/shm/nginx_unixsocket/h2.sock http2 default_server;
    return 301 https://${domain_list[0]};
}
EOF
    for ((i=0;i<${#domain_list[@]};i++))
    do
cat >> $nginx_config<<EOF
server {
    listen unix:/dev/shm/nginx_unixsocket/default.sock;
    listen unix:/dev/shm/nginx_unixsocket/h2.sock http2;
    server_name ${domain_list[$i]};
    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload" always;
EOF
        if [ "${pretend_list[$i]}" == "1" ]; then
cat >> $nginx_config<<EOF
    location / {
        proxy_set_header X-Forwarded-For 127.0.0.1;
        proxy_set_header Host 127.0.0.1:443;
        proxy_redirect off;
        proxy_pass http://unix:/dev/shm/cloudreve_unixsocket/cloudreve.sock;
        client_max_body_size 0;
    }
EOF
        elif [ "${pretend_list[$i]}" == "2" ]; then
            echo "    root ${nginx_prefix}/html/${true_domain_list[$i]};" >> $nginx_config
            echo "    include ${nginx_prefix}/conf.d/nextcloud.conf;" >> $nginx_config
        elif [ "${pretend_list[$i]}" == "3" ]; then
            echo "    return 403;" >> $nginx_config
        elif [ "${pretend_list[$i]}" == "4" ]; then
            echo "    root ${nginx_prefix}/html/${true_domain_list[$i]};" >> $nginx_config
        else
cat >> $nginx_config<<EOF
    location / {
        proxy_pass ${pretend_list[$i]};
        proxy_set_header referer "${pretend_list[$i]}";
    }
EOF
        fi
        echo "}" >> $nginx_config
    done
cat >> $nginx_config << EOF
#-----------------不要修改以下内容----------------
#domain_list=${domain_list[@]}
#true_domain_list=${true_domain_list[@]}
#domain_config_list=${domain_config_list[@]}
#pretend_list=${pretend_list[@]}
EOF
}

#配置xray
config_xray()
{
    local i
    local temp_domain
cat > $xray_config <<EOF
{
    "log": {
        "loglevel": "none"
    },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
EOF
    if [ $protocol_1 -eq 1 ]; then
cat >> $xray_config <<EOF
                "clients": [
                    {
                        "id": "$xid_1",
                        "flow": "xtls-rprx-direct"
                    }
                ],
EOF
    fi
    echo '                "decryption": "none",' >> $xray_config
    echo '                "fallbacks": [' >> $xray_config
    if [ $protocol_2 -ne 0 ]; then
cat >> $xray_config <<EOF
                    {
                        "path": "$path",
                        "dest": "@/dev/shm/xray/ws.sock"
                    },
EOF
    fi
cat >> $xray_config <<EOF
                    {
                        "alpn": "h2",
                        "dest": "/dev/shm/nginx_unixsocket/h2.sock"
                    },
                    {
                        "dest": "/dev/shm/nginx_unixsocket/default.sock"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "alpn": [
                        "h2",
                        "http/1.1"
                    ],
                    "minVersion": "1.2",
                    "cipherSuites": "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256:TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384:TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
                    "certificates": [
EOF
    for ((i=0;i<${#true_domain_list[@]};i++))
    do
cat >> $xray_config <<EOF
                        {
                            "certificateFile": "${nginx_prefix}/certs/${true_domain_list[$i]}.cer",
                            "keyFile": "${nginx_prefix}/certs/${true_domain_list[$i]}.key",
                            "ocspStapling": 3600
EOF
        ((i==${#true_domain_list[@]}-1)) && echo "                        }" >> $xray_config || echo "                        }," >> $xray_config
    done
cat >> $xray_config <<EOF
                    ]
                }
            }
EOF
    if [ $protocol_2 -ne 0 ]; then
        echo '        },' >> $xray_config
        echo '        {' >> $xray_config
        echo '            "listen": "@/dev/shm/xray/ws.sock",' >> $xray_config
        if [ $protocol_2 -eq 2 ]; then
            echo '            "protocol": "vmess",' >> $xray_config
        else
            echo '            "protocol": "vless",' >> $xray_config
        fi
        echo '            "settings": {' >> $xray_config
        echo '                "clients": [' >> $xray_config
        echo '                    {' >> $xray_config
        echo "                        \"id\": \"$xid_2\"" >> $xray_config
        echo '                    }' >> $xray_config
        if [ $protocol_2 -eq 2 ]; then
            echo '                ]' >> $xray_config
        else
            echo '                ],' >> $xray_config
            echo '                "decryption": "none"' >> $xray_config
        fi
cat >> $xray_config <<EOF
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$path"
                }
            }
EOF
    fi
cat >> $xray_config <<EOF
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom"
        }
    ]
}
EOF
}

#下载nextcloud模板，用于伪装    参数：域名在列表中的位置
init_web()
{
    if ! ([ "${pretend_list[$1]}" == "2" ] || [ "${pretend_list[$1]}" == "4" ]); then
        return 0
    fi
    local url
    [ ${pretend_list[$1]} -eq 2 ] && url="${nextcloud_url}" || url="https://github.com/kirin10000/Xray-script/raw/main/Website-Template.zip"
    local info
    [ ${pretend_list[$1]} -eq 2 ] && info="Nextcloud" || info="网站模板"
    if ! wget -O "${nginx_prefix}/html/Website.zip" "$url"; then
        red    "获取${info}失败"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    fi
    rm -rf "${nginx_prefix}/html/${true_domain_list[$1]}"
    if [ ${pretend_list[$1]} -eq 4 ]; then
        mkdir "${nginx_prefix}/html/${true_domain_list[$1]}"
        unzip -q -d "${nginx_prefix}/html/${true_domain_list[$1]}" "${nginx_prefix}/html/Website.zip"
    else
        unzip -q -d "${nginx_prefix}/html" "${nginx_prefix}/html/Website.zip"
        mv "${nginx_prefix}/html/nextcloud" "${nginx_prefix}/html/${true_domain_list[$1]}"
        chown -R www-data:www-data "${nginx_prefix}/html/${true_domain_list[$1]}"
    fi
    rm -rf "${nginx_prefix}/html/Website.zip"
}
init_all_webs()
{
    local i
    for ((i=0;i<${#domain_list[@]};i++))
    do
        init_web "$i"
    done
}

#安装/更新Cloudreve
update_cloudreve()
{
    if ! wget -O cloudreve.tar.gz "https://github.com/cloudreve/Cloudreve/releases/download/${cloudreve_version}/cloudreve_${cloudreve_version}_linux_${machine}.tar.gz"; then
        red "获取Cloudreve失败！！"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    fi
    tar -zxf cloudreve.tar.gz
    local temp_cloudreve_status=0
    systemctl -q is-active cloudreve && temp_cloudreve_status=1
    systemctl stop cloudreve
    cp cloudreve $cloudreve_prefix
cat > $cloudreve_prefix/conf.ini << EOF
[System]
Mode = master
Debug = false
[UnixSocket]
Listen = /dev/shm/cloudreve_unixsocket/cloudreve.sock
EOF
    rm -rf $cloudreve_service
cat > $cloudreve_service << EOF
[Unit]
Description=Cloudreve
Documentation=https://docs.cloudreve.org
After=network.target
After=mysqld.service
Wants=network.target

[Service]
WorkingDirectory=$cloudreve_prefix
ExecStartPre=/bin/rm -rf /dev/shm/cloudreve_unixsocket
ExecStartPre=/bin/mkdir /dev/shm/cloudreve_unixsocket
ExecStartPre=/bin/chmod 711 /dev/shm/cloudreve_unixsocket
ExecStart=$cloudreve_prefix/cloudreve
ExecStopPost=/bin/rm -rf /dev/shm/cloudreve_unixsocket
Restart=on-abnormal
RestartSec=5s
KillMode=mixed

StandardOutput=null
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    [ $temp_cloudreve_status -eq 1 ] && systemctl start cloudreve
}
install_init_cloudreve()
{
    remove_cloudreve
    mkdir -p $cloudreve_prefix
    update_cloudreve
    init_cloudreve "$1"
    cloudreve_is_installed=1
}

#初始化nextcloud 参数 1:域名在列表中的位置
let_init_nextcloud()
{
    echo -e "\\n\\n"
    yellow "请立即打开\"https://${domain_list[$1]}\"进行Nextcloud初始化设置："
    tyblue " 1.自定义管理员的用户名和密码"
    tyblue " 2.数据库类型选择SQLite"
    tyblue " 3.建议不勾选\"安装推荐的应用\"，因为进去之后还能再安装"
    sleep 15s
    echo -e "\\n\\n"
    tyblue "按两次回车键以继续。。。"
    read -s
    read -s
    echo
}

print_share_link()
{
    if [ $protocol_1 -eq 1 ]; then
        local ip=""
        while [ -z "$ip" ]
        do
            read -p "请输入您的VPS IP：" ip
        done
    fi
    echo
    tyblue "分享链接："
    if [ $protocol_1 -eq 1 ]; then
        green  "VLESS-TCP+XTLS\\033[35m(不走CDN)\\033[32m："
        yellow " Linux/安卓/路由器："
        for i in ${!domain_list[@]}
        do
            tyblue " vless://${xid_1}@${ip}:443?security=xtls&sni=${domain_list[$i]}&flow=xtls-rprx-splice"
        done
        yellow " 其他："
        for i in ${!domain_list[@]}
        do
            tyblue " vless://${xid_1}@${ip}:443?security=xtls&sni=${domain_list[$i]}&flow=xtls-rprx-direct"
        done
    fi
    if [ $protocol_2 -eq 1 ]; then
        green  "VLESS-WebSocket+TLS\\033[35m(有CDN则走CDN，否则直连)\\033[32m："
        for i in ${!domain_list[@]}
        do
            tyblue "vless://${xid_2}@${domain_list[$i]}:443?type=ws&security=tls&path=%2F${path#/}"
        done
    elif [ $protocol_2 -eq 2 ]; then
        green  "VMess-WebSocket+TLS\\033[35m(有CDN则走CDN，否则直连)\\033[32m："
        for i in ${!domain_list[@]}
        do
            tyblue "vmess://${xid_2}@${domain_list[$i]}:443?type=ws&security=tls&path=%2F${path#/}"
        done
    fi
}
print_config_info()
{
    echo -e "\\n\\n\\n"
    if [ $protocol_1 -ne 0 ]; then
        tyblue "---------------------- Xray-TCP+XTLS+Web (不走CDN) ---------------------"
        tyblue " 服务器类型            ：VLESS"
        tyblue " address(地址)         ：服务器ip"
        purple "  (Qv2ray:主机)"
        tyblue " port(端口)            ：443"
        tyblue " id(用户ID/UUID)       ：${xid_1}"
        tyblue " flow(流控)            ：使用XTLS ：Linux/安卓/路由器:xtls-rprx-splice\\033[32m(推荐)\\033[36m或xtls-rprx-direct"
        tyblue "                                    其它:xtls-rprx-direct"
        tyblue "                         使用TLS  ：空"
        tyblue " encryption(加密)      ：none"
        tyblue " ---Transport/StreamSettings(底层传输方式/流设置)---"
        tyblue "  network(传输协议)             ：tcp"
        purple "   (Shadowrocket:传输方式:none)"
        tyblue "  type(伪装类型)                ：none"
        purple "   (Qv2ray:协议设置-类型)"
        tyblue "  security(传输层加密)          ：xtls\\033[32m(推荐)\\033[36m或tls \\033[35m(此选项将决定是使用XTLS还是TLS)"
        purple "   (V2RayN(G):底层传输安全;Qv2ray:TLS设置-安全类型)"
        if [ ${#domain_list[@]} -eq 1 ]; then
            tyblue "  serverName                    ：${domain_list[*]}"
        else
            tyblue "  serverName                    ：${domain_list[*]} \\033[35m(任选其一)"
        fi
        purple "   (V2RayN(G):伪装域名;Qv2ray:TLS设置-服务器地址;Shadowrocket:Peer 名称)"
        tyblue "  allowInsecure                 ：false"
        purple "   (Qv2ray:允许不安全的证书(不打勾);Shadowrocket:允许不安全(关闭))"
        tyblue " ------------------------其他-----------------------"
        tyblue "  Mux(多路复用)                 ：使用XTLS必须关闭;不使用XTLS也建议关闭"
        tyblue "  socks入站的Sniffing(流量探测) ：建议开启"
        purple "   (Qv2ray:首选项-入站设置-SOCKS设置-嗅探)"
        tyblue "------------------------------------------------------------------------"
    fi
    if [ $protocol_2 -ne 0 ]; then
        echo
        tyblue "------------ Xray-WebSocket+TLS+Web (有CDN则走CDN，否则直连) -----------"
        if [ $protocol_2 -eq 1 ]; then
            tyblue " 服务器类型            ：VLESS"
        else
            tyblue " 服务器类型            ：VMess"
        fi
        if [ ${#domain_list[@]} -eq 1 ]; then
            tyblue " address(地址)         ：${domain_list[*]}"
        else
            tyblue " address(地址)         ：${domain_list[*]} \\033[35m(任选其一)"
        fi
        purple "  (Qv2ray:主机)"
        tyblue " port(端口)            ：443"
        tyblue " id(用户ID/UUID)       ：${xid_2}"
        if [ $protocol_2 -eq 1 ]; then
            tyblue " flow(流控)            ：空"
            tyblue " encryption(加密)      ：none"
        else
            tyblue " alterId(额外ID)       ：0"
            tyblue " security(加密方式)    ：使用CDN，推荐auto;不使用CDN，推荐none"
            purple "  (Qv2ray:安全选项;Shadowrocket:算法)"
        fi
        tyblue " ---Transport/StreamSettings(底层传输方式/流设置)---"
        tyblue "  network(传输协议)             ：ws"
        purple "   (Shadowrocket:传输方式:websocket)"
        tyblue "  path(路径)                    ：${path}"
        tyblue "  Host                          ：空"
        purple "   (V2RayN(G):伪装域名;Qv2ray:协议设置-请求头)"
        tyblue "  security(传输层加密)          ：tls"
        purple "   (V2RayN(G):底层传输安全;Qv2ray:TLS设置-安全类型)"
        tyblue "  serverName(验证服务端证书域名)：空"
        purple "   (V2RayN(G):伪装域名;Qv2ray:TLS设置-服务器地址;Shadowrocket:Peer 名称)"
        tyblue "  allowInsecure                 ：false"
        purple "   (Qv2ray:允许不安全的证书(不打勾);Shadowrocket:允许不安全(关闭))"
        tyblue " ------------------------其他-----------------------"
        tyblue "  Mux(多路复用)                 ：建议关闭"
        tyblue "  socks入站的Sniffing(流量探测) ：建议开启"
        purple "   (Qv2ray:首选项-入站设置-SOCKS设置-嗅探)"
        tyblue "------------------------------------------------------------------------"
    fi
    echo
    ask_if "是否生成分享链接？(y/n)" && print_share_link
    echo
    green  " 目前支持支持XTLS的图形化客户端："
    green  "   Windows    ：Qv2ray       v2.7.0-pre1+    V2RayN  v3.26+"
    green  "   Android    ：V2RayNG      v1.4.8+"
    green  "   Linux/MacOS：Qv2ray       v2.7.0-pre1+"
    green  "   IOS        ：Shadowrocket v2.1.67+"
    echo
    yellow " 若使用VMess，请尽快将客户端更新至 Xray 或 V2Ray v4.28.0+ 以启用VMessAEAD"
    yellow " 若使用VLESS，请确保客户端为 Xray 或 V2Ray v4.30.0+"
    yellow " 若使用XTLS，请确保客户端为 Xray 或 V2Ray v4.31.0至v4.32.1"
    yellow " 若使用xtls-rprx-splice，请确保客户端为 Xray v1.1.0+"
    echo
    tyblue " 脚本最后更新时间：2020.01.18"
    echo
    red    " 此脚本仅供交流学习使用，请勿使用此脚本行违法之事。网络非法外之地，行非法之事，必将接受法律制裁!!!!"
    tyblue " 2020.11"
}

install_update_xray_tls_web()
{
    check_nginx_installed_system
    check_SELinux
    check_important_dependence_installed net-tools net-tools
    check_port
    check_important_dependence_installed lsb-release redhat-lsb-core
    get_system_info
    check_important_dependence_installed ca-certificates ca-certificates
    check_important_dependence_installed wget wget
    check_ssh_timeout
    uninstall_firewall
    doupdate
    enter_temp_dir
    install_bbr
    $debian_package_manager -y -f install

    #读取信息
    if [ $update -eq 0 ]; then
        readProtocolConfig
        readDomain
        path="/$(head -c 8 /dev/urandom | md5sum | head -c 7)"
        xid_1="$(cat /proc/sys/kernel/random/uuid)"
        xid_2="$(cat /proc/sys/kernel/random/uuid)"
    else
        get_config_info
    fi

    local choice

    local install_php
    if [ $update -eq 0 ]; then
        [ "${pretend_list[0]}" == "2" ] && install_php=1 || install_php=0
    else
        install_php=$php_is_installed
    fi
    local use_existed_php=0
    if [ $install_php -eq 1 ]; then
        if [ $update -eq 1 ]; then
            if check_php_update; then
                ! ask_if "检测到php有新版本，是否更新?(y/n)" && use_existed_php=1
            else
                green "php已经是最新版本，不更新"
                use_existed_php=1
            fi
        elif [ $php_is_installed -eq 1 ]; then
            tyblue "---------------检测到php已存在---------------"
            tyblue " 1. 使用现有php"
            tyblue " 2. 卸载现有php并重新编译安装"
            echo
            choice=""
            while [ "$choice" != "1" ] && [ "$choice" != "2" ]
            do
                read -p "您的选择是：" choice
            done
            [ $choice -eq 1 ] && use_existed_php=1
        fi
    fi

    local use_existed_nginx=0
    if [ $update -eq 1 ]; then
        if check_nginx_update; then
            ! ask_if "检测到Nginx有新版本，是否更新?(y/n)" && use_existed_nginx=1
        else
            green "Nginx已经是最新版本，不更新"
            use_existed_nginx=1
        fi
    elif [ $nginx_is_installed -eq 1 ]; then
        tyblue "---------------检测到Nginx已存在---------------"
        tyblue " 1. 使用现有Nginx"
        tyblue " 2. 卸载现有Nginx并重新编译安装"
        echo
        choice=""
        while [ "$choice" != "1" ] && [ "$choice" != "2" ]
        do
            read -p "您的选择是：" choice
        done
        [ $choice -eq 1 ] && use_existed_nginx=1
    fi
    #此参数只在[ $update -eq 0 ]时有效
    local temp_remove_cloudreve=1
    if [ $update -eq 0 ] && [ "${pretend_list[0]}" == "1" ] && [ $cloudreve_is_installed -eq 1 ]; then
        tyblue "----------------- Cloudreve已存在 -----------------"
        tyblue " 1. 使用现有Cloudreve"
        tyblue " 2. 卸载并重新安装"
        echo
        red    "警告：卸载Cloudreve将删除网盘中所有文件和用户信息"
        choice=""
        while [ "$choice" != "1" ] && [ "$choice" != "2" ]
        do
            read -p "您的选择是：" choice
        done
        [ $choice -eq 1 ] && temp_remove_cloudreve=0
    fi

    green "正在安装依赖。。。。"
    install_base_dependence
    install_nginx_dependence
    [ $install_php -eq 1 ] && install_php_dependence
    $debian_package_manager clean
    $redhat_package_manager clean all

    #编译&&安装php
    if [ $install_php -eq 1 ]; then
        if [ $use_existed_php -eq 0 ]; then
            compile_php
            remove_php
            install_php_part1
        else
            systemctl --now disable php-fpm
        fi
        install_php_part2
        [ $update -eq 1 ] && turn_on_off_php
    fi

    #编译&&安装Nginx
    if [ $use_existed_nginx -eq 0 ]; then
        compile_nginx
        [ $update -eq 1 ] && backup_domains_web
        remove_nginx
        install_nginx_part1
    else
        systemctl --now disable nginx
        rm -rf ${nginx_prefix}/conf.d
        rm -rf ${nginx_prefix}/certs
        rm -rf ${nginx_prefix}/html/issue_certs
        rm -rf ${nginx_prefix}/conf/issue_certs.conf
        cp ${nginx_prefix}/conf/nginx.conf.default ${nginx_prefix}/conf/nginx.conf
    fi
    install_nginx_part2
    [ $update -eq 1 ] && [ $use_existed_nginx -eq 0 ] && mv "${temp_dir}/domain_backup/"* ${nginx_prefix}/html 2>/dev/null

    #安装Xray
    remove_xray
    install_update_xray

    green "正在获取证书。。。。"
    if [ $update -eq 0 ]; then
        [ -e $HOME/.acme.sh/acme.sh ] && $HOME/.acme.sh/acme.sh --uninstall
        rm -rf $HOME/.acme.sh
        curl https://get.acme.sh | sh
    fi
    $HOME/.acme.sh/acme.sh --upgrade --auto-upgrade
    get_all_certs

    #配置Nginx和Xray
    config_nginx
    config_xray
    [ $update -eq 0 ] && init_all_webs
    sleep 2s
    systemctl restart xray nginx
    if [ $update -eq 0 ]; then
        if [ "${pretend_list[0]}" == "2" ]; then
            systemctl --now enable php-fpm
            let_init_nextcloud "0"
        else
            systemctl --now disable php-fpm
        fi
        if [ "${pretend_list[0]}" == "1" ]; then
            if [ $temp_remove_cloudreve -eq 1 ]; then
                install_init_cloudreve "0"
            else
                systemctl --now enable cloudreve
                update_cloudreve
                let_change_cloudreve_domain "0"
            fi
        else
            systemctl --now disable cloudreve
        fi
        green "-------------------安装完成-------------------"
        print_config_info
    else
        [ $cloudreve_is_installed -eq 1 ] && update_cloudreve
        turn_on_off_cloudreve
        green "-------------------更新完成-------------------"
    fi
    cd /
    rm -rf "$temp_dir"
}

#功能型函数
check_script_update()
{
    if [[ -z "${BASH_SOURCE[0]}" ]]; then
        red "脚本不是文件，无法检查更新"
        exit 1
    fi
    [ "$(md5sum "${BASH_SOURCE[0]}" | awk '{print $1}')" == "$(md5sum <(wget -O - "https://github.com/kirin10000/Xray-script/raw/main/Xray-TLS+Web-setup.sh") | awk '{print $1}')" ] && return 1 || return 0
}
update_script()
{
    if [[ -z "${BASH_SOURCE[0]}" ]]; then
        red "脚本不是文件，无法更新"
        return 1
    fi
    rm -rf "${BASH_SOURCE[0]}"
    if ! wget -O "${BASH_SOURCE[0]}" "https://github.com/kirin10000/Xray-script/raw/main/Xray-TLS+Web-setup.sh" && ! wget -O "${BASH_SOURCE[0]}" "https://github.com/kirin10000/Xray-script/raw/main/Xray-TLS+Web-setup.sh"; then
        red "更新脚本失败！"
        yellow "按回车键继续或Ctrl+c中止"
        read -s
    fi
}
full_install_php()
{
    install_base_dependence
    install_php_dependence
    enter_temp_dir
    compile_php
    remove_php
    install_php_part1
    install_php_part2
    cd /
    rm -rf "$temp_dir"
}
#安装/检查更新/更新php
install_check_update_update_php()
{
    check_script_update && red "脚本可升级，请先更新脚本" && return 1
    if [ $php_is_installed -eq 1 ]; then
        if check_php_update; then
            green "php有新版本"
            ! ask_if "是否更新？(y/n)" && return 0
        else
            green "php已是最新版本"
            return 0
        fi
    fi
    local php_status=0
    systemctl -q is-active php-fpm && php_status=1
    full_install_php
    turn_on_off_php
    if [ $php_status -eq 1 ]; then
        systemctl start php-fpm
    else
        systemctl stop php-fpm
    fi
    green "更新完成！"
}
check_update_update_nginx()
{
    check_script_update && red "脚本可升级，请先更新脚本" && return 1
    if check_nginx_update; then
        green "Nginx有新版本"
        ! ask_if "是否更新？(y/n)" && return 0
    else
        green "Nginx已是最新版本"
        return 0
    fi
    local nginx_status=0
    local xray_status=0
    systemctl -q is-active nginx && nginx_status=1
    systemctl -q is-active xray && xray_status=1
    install_base_dependence
    install_nginx_dependence
    enter_temp_dir
    compile_nginx
    backup_domains_web
    remove_nginx
    install_nginx_part1
    install_nginx_part2
    config_nginx
    mv "${temp_dir}/domain_backup/"* ${nginx_prefix}/html 2>/dev/null
    get_all_certs
    if [ $nginx_status -eq 1 ]; then
        systemctl restart nginx
    else
        systemctl stop nginx
    fi
    if [ $xray_status -eq 1 ]; then
        systemctl restart xray
    else
        systemctl stop xray
    fi
    cd /
    rm -rf "$temp_dir"
    green "更新完成！"
}
full_install_init_cloudreve()
{
    enter_temp_dir
    install_init_cloudreve "$1"
    cd /
    rm -rf "$temp_dir"
}
reinit_domain()
{
    yellow "重置域名将删除所有现有域名(包括域名证书、伪装网站等)"
    ! ask_if "是否继续？(y/n)" && return 0
    readDomain
    [ "${pretend_list[-1]}" == "2" ] && [ $php_is_installed -eq 0 ] && full_install_php
    green "重置域名中。。。"
    local temp_domain="${domain_list[-1]}"
    local temp_true_domain="${true_domain_list[-1]}"
    local temp_domain_config="${domain_config_list[-1]}"
    local temp_pretend="${pretend_list[-1]}"
    unset 'domain_list[-1]'
    unset 'true_domain_list[-1]'
    unset 'domain_config_list[-1]'
    unset 'pretend_list[-1]'
    remove_all_domains
    domain_list+=("$temp_domain")
    domain_config_list+=("$temp_domain_config")
    true_domain_list+=("$temp_true_domain")
    pretend_list+=("$temp_pretend")
    get_all_certs
    config_nginx
    config_xray
    init_all_webs
    sleep 2s
    systemctl restart xray nginx
    if [ "${pretend_list[0]}" == "2" ]; then
        systemctl --now enable php-fpm
        let_init_nextcloud "0"
    elif [ "${pretend_list[0]}" == "1" ]; then
        if [ $cloudreve_is_installed -eq 0 ]; then
            full_install_init_cloudreve "0"
        else
            systemctl --now enable cloudreve
            let_change_cloudreve_domain "0"
        fi
    fi
    green "域名重置完成！！"
    print_config_info
}
add_domain()
{
    local need_cloudreve=0
    check_need_cloudreve && need_cloudreve=1
    readDomain
    if [ "${pretend_list[-1]}" == "1" ] && [ $need_cloudreve -eq 1 ]; then
        yellow "Cloudreve只能用于一个域名！！"
        tyblue "Nextcloud可以用于多个域名"
        return 1
    fi
    [ "${pretend_list[-1]}" == "2" ] && [ $php_is_installed -eq 0 ] && full_install_php
    if ! get_cert "-1"; then
        sleep 2s
        systemctl restart xray nginx
        red "申请证书失败！！"
        red "域名添加失败"
        return 1
    fi
    init_web "-1"
    config_nginx
    config_xray
    sleep 2s
    systemctl restart xray nginx
    turn_on_off_php
    [ "${pretend_list[-1]}" == "2" ] && let_init_nextcloud "-1"
    if [ "${pretend_list[-1]}" == "1" ]; then
        if [ $cloudreve_is_installed -eq 0 ]; then
            full_install_init_cloudreve "-1"
        else
            systemctl --now enable cloudreve
            let_change_cloudreve_domain "-1"
        fi
    fi
    green "域名添加完成！！"
    print_config_info
}
delete_domain()
{
    if [ ${#domain_list[@]} -le 1 ]; then
        red "只有一个域名"
        return 1
    fi
    local i
    tyblue "-----------------------请选择要删除的域名-----------------------"
    for i in ${!domain_list[@]}
    do
        if [ ${domain_config_list[$i]} -eq 1 ]; then
            tyblue " $((i+1)). ${domain_list[$i]} ${true_domain_list[$i]}"
        else
            tyblue " $((i+1)). ${domain_list[$i]}"
        fi
    done
    yellow " 0. 不删除"
    local delete=""
    while ! [[ "$delete" =~ ^([1-9][0-9]*|0)$ ]] || [ $delete -gt ${#domain_list[@]} ]
    do
        read -p "你的选择是：" delete
    done
    [ $delete -eq 0 ] && return 0
    ((delete--))
    $HOME/.acme.sh/acme.sh --remove --domain ${true_domain_list[$delete]} --ecc
    rm -rf $HOME/.acme.sh/${true_domain_list[$delete]}_ecc
    rm -rf "${nginx_prefix}/certs/${true_domain_list[$delete]}.key" "${nginx_prefix}/certs/${true_domain_list[$delete]}.cer"
    rm -rf ${nginx_prefix}/html/${true_domain_list[$delete]}
    unset 'domain_list[$delete]'
    unset 'true_domain_list[$delete]'
    unset 'domain_config_list[$delete]'
    unset 'pretend_list[$delete]'
    domain_list=("${domain_list[@]}")
    true_domain_list=("${true_domain_list[@]}")
    domain_config_list=("${domain_config_list[@]}")
    pretend_list=("${pretend_list[@]}")
    config_nginx
    config_xray
    systemctl restart xray nginx
    turn_on_off_php
    turn_on_off_cloudreve
    green "域名删除完成！！"
    print_config_info
}
reinit_cloudreve()
{
    ! check_need_cloudreve && red "Cloudreve目前没有绑定域名" && return 1
    red "重置Cloudreve将删除所有的Cloudreve网盘文件以及帐户信息，相当于重新安装"
    tyblue "管理员密码忘记可以用此选项恢复"
    ! ask_if "确定要继续吗？(y/n)" && return 0
    local i
    for i in ${!pretend_list[@]}
    do
        [ "${pretend_list[$i]}" == "1" ] && break
    done
    systemctl stop cloudreve
    sleep 1s
    shopt -s extglob
    temp="rm -rf $cloudreve_prefix/!(cloudreve|conf.ini)"
    $temp
    init_cloudreve "$i"
    green "重置完成！"
}
change_pretend()
{
    local change=""
    if [ ${#domain_list[@]} -eq 1 ]; then
        change=0
    else
        local i
        tyblue "-----------------------请选择要修改伪装类型的域名-----------------------"
        for i in ${!domain_list[@]}
        do
            if [ ${domain_config_list[$i]} -eq 1 ]; then
                tyblue " $((i+1)). ${domain_list[$i]} ${true_domain_list[$i]}"
            else
                tyblue " $((i+1)). ${domain_list[$i]}"
            fi
        done
        yellow " 0. 不修改"
        while ! [[ "$change" =~ ^([1-9][0-9]*|0)$ ]] || [ $change -gt ${#domain_list[@]} ]
        do
            read -p "你的选择是：" change
        done
        [ $change -eq 0 ] && return 0
        ((change--))
    fi
    local pretend
    readPretend
    if [ "${pretend_list[$change]}" == "$pretend" ]; then
        yellow "伪装类型没有变化"
        return 1
    fi
    local need_cloudreve=0
    check_need_cloudreve && need_cloudreve=1
    pretend_list[$change]="$pretend"
    if [ "$pretend" == "1" ] && [ $need_cloudreve -eq 1 ]; then
        yellow "Cloudreve只能用于一个域名！！"
        tyblue "Nextcloud可以用于多个域名"
        return 1
    fi
    [ "$pretend" == "2" ] && [ $php_is_installed -eq 0 ] && full_install_php
    init_web "$change"
    config_nginx
    systemctl restart nginx
    turn_on_off_php
    [ "$pretend" == "2" ] && let_init_nextcloud "$change"
    if [ "$pretend" == "1" ]; then
        if [ $cloudreve_is_installed -eq 0 ]; then
            full_install_init_cloudreve "$change"
        else
            systemctl --now enable cloudreve
            let_change_cloudreve_domain "$change"
        fi
    else
        turn_on_off_cloudreve
    fi
    green "修改完成！"
}
change_xray_id()
{
    local flag=""
    if [ $protocol_1 -ne 0 ] && [ $protocol_2 -ne 0 ]; then
        tyblue "-------------请输入你要修改的id-------------"
        tyblue " 1. Xray-TCP+XTLS 的id"
        tyblue " 2. Xray-WebSocket+TLS 的id"
        echo
        while [ "$flag" != "1" ] && [ "$flag" != "2" ]
        do
            read -p "您的选择是：" flag
        done
    elif [ $protocol_1 -ne 0 ]; then
        flag=1
    else
        flag=2
    fi
    local xid="xid_$flag"
    tyblue "您现在的id是：${!xid}"
    ! ask_if "是否要继续?(y/n)" && return 0
    xid=""
    while [ -z "$xid" ]
    do
        tyblue "-------------请输入新的id-------------"
        read xid
    done
    [ $flag -eq 1 ] && xid_1="$xid" || xid_2="$xid"
    config_xray
    systemctl -q is-active xray && systemctl restart xray
    green "更换成功！！"
    print_config_info
}
change_xray_path()
{
    if [ $protocol_2 -eq 0 ]; then
        red "Xray-TCP+XTLS+Web模式没有path!!"
        return 1
    fi
    tyblue "您现在的path是：$path"
    ! ask_if "是否要继续?(y/n)" && return 0
    path=""
    while [ -z "$path" ]
    do
        tyblue "---------------请输入新的path(带\"/\")---------------"
        read path
    done
    config_xray
    systemctl -q is-active xray && systemctl restart xray
    green "更换成功！！"
    print_config_info
}
change_xray_protocol()
{
    local protocol_1_old=$protocol_1
    local protocol_2_old=$protocol_2
    readProtocolConfig
    if [ $protocol_1_old -eq $protocol_1 ] && [ $protocol_2_old -eq $protocol_2 ]; then
        red "传输协议未更换"
        return 1
    fi
    [ $protocol_1_old -eq 0 ] && [ $protocol_1 -ne 0 ] && xid_1=$(cat /proc/sys/kernel/random/uuid)
    if [ $protocol_2_old -eq 0 ] && [ $protocol_2 -ne 0 ]; then
        path="/$(head -c 8 /dev/urandom | md5sum | head -c 7)"
        xid_2=$(cat /proc/sys/kernel/random/uuid)
    fi
    config_xray
    systemctl -q is-active xray && systemctl restart xray
    green "更换成功！！"
    print_config_info
}
simplify_system()
{
    if systemctl -q is-active xray || systemctl -q is-active nginx || systemctl -q is-active php-fpm; then
        yellow "请先停止Xray-TLS+Web"
        return 1
    fi
    yellow "警告：如果服务器上有运行别的程序，可能会被误删"
    tyblue "建议在纯净系统下使用此功能"
    ! ask_if "是否要继续?(y/n)" && return 0
    if [ $release == "centos" ] || [ $release == "fedora" ] || [ $release == "other-redhat" ]; then
        $redhat_package_manager -y remove openssl "perl*"
    else
        local temp_remove_list=('openssl' 'snapd' 'kdump-tools' 'flex' 'make' 'automake' '^cloud-init' 'pkg-config' '^gcc-[1-9][0-9]*$' 'libffi-dev' '^cpp-[1-9][0-9]*$' 'curl' '^python' '^libpython' 'dbus' 'cron' 'at' 'open-iscsi' 'rsyslog' 'anacron' 'acpid')
        if ! $debian_package_manager -y --autoremove purge "${temp_remove_list[@]}"; then
            $debian_package_manager -y -f install
            for i in ${!temp_remove_list[@]}
            do
                $debian_package_manager -y --autoremove purge "${temp_remove_list[$i]}"
            done
            $debian_package_manager -y -f install
        fi
        [ $release == "ubuntu" ] && check_important_dependence_installed netplan.io
    fi
    check_important_dependence_installed openssh-server openssh-server
    [ $nginx_is_installed -eq 1 ] && install_nginx_dependence
    [ $php_is_installed -eq 1 ] && install_php_dependence
    [ $is_installed -eq 1 ] && install_base_dependence
    green "精简完成"
}
repair_tuige()
{
    yellow "尝试修复退格键异常问题，退格键正常请不要修复"
    ! ask_if "是否要继续?(y/n)" && return 0
    if stty -a | grep -q 'erase = ^?'; then
        stty erase '^H'
    elif stty -a | grep -q 'erase = ^H'; then
        stty erase '^?'
    fi
    green "修复完成！！"
}
change_dns()
{
    red    "注意！！"
    red    "1.部分云服务商(如阿里云)使用本地服务器作为软件包源，修改dns后需要换源！！"
    red    "  如果不明白，那么请在安装完成后再修改dns，并且修改完后不要重新安装"
    red    "2.Ubuntu系统重启后可能会恢复原dns"
    tyblue "此操作将修改dns服务器为1.1.1.1和1.0.0.1(cloudflare公共dns)"
    ! ask_if "是否要继续?(y/n)" && return 0
    if ! grep -q "#This file has been edited by Xray-TLS-Web-setup-script" /etc/resolv.conf; then
        sed -i 's/^[ \t]*nameserver[ \t][ \t]*/#&/' /etc/resolv.conf
        {
            echo
            echo 'nameserver 1.1.1.1'
            echo 'nameserver 1.0.0.1'
            echo '#This file has been edited by Xray-TLS-Web-setup-script'
        } >> /etc/resolv.conf
    fi
    green "修改完成！！"
}
#开始菜单
start_menu()
{
    local xray_status
    [ $xray_is_installed -eq 1 ] && xray_status="\\033[32m已安装" || xray_status="\\033[31m未安装"
    systemctl -q is-active xray && xray_status+="                \\033[32m运行中" || xray_status+="                \\033[31m未运行"
    local nginx_status
    [ $nginx_is_installed -eq 1 ] && nginx_status="\\033[32m已安装" || nginx_status="\\033[31m未安装"
    systemctl -q is-active nginx && nginx_status+="                \\033[32m运行中" || nginx_status+="                \\033[31m未运行"
    local php_status
    [ $php_is_installed -eq 1 ] && php_status="\\033[32m已安装" || php_status="\\033[31m未安装"
    systemctl -q is-active php-fpm && php_status+="                \\033[32m运行中" || php_status+="                \\033[31m未运行"
    local cloudreve_status
    [ $cloudreve_is_installed -eq 1 ] && cloudreve_status="\\033[32m已安装" || cloudreve_status="\\033[31m未安装"
    systemctl -q is-active cloudreve && cloudreve_status+="                \\033[32m运行中" || cloudreve_status+="                \\033[31m未运行"
    tyblue "---------------------- Xray-TLS(1.3)+Web 搭建/管理脚本 ---------------------"
    echo
    tyblue "           Xray   ：           ${xray_status}"
    echo
    tyblue "           Nginx  ：           ${nginx_status}"
    echo
    tyblue "           php    ：           ${php_status}"
    echo
    tyblue "        Cloudreve ：           ${cloudreve_status}"
    echo
    tyblue "       官网：https://github.com/kirin10000/Xray-script"
    echo
    tyblue "----------------------------------注意事项----------------------------------"
    yellow " 1. 此脚本需要一个解析到本服务器的域名"
    tyblue " 2. 此脚本安装时间较长，详细原因见："
    tyblue "       https://github.com/kirin10000/Xray-script#安装时长说明"
    green  " 3. 建议使用纯净的系统 (VPS控制台-重置系统)"
    green  " 4. 推荐使用Ubuntu最新版系统"
    tyblue "----------------------------------------------------------------------------"
    echo
    echo
    tyblue " -----------安装/更新/卸载-----------"
    if [ $is_installed -eq 0 ]; then
        green  "   1. 安装Xray-TLS+Web"
    else
        green  "   1. 重新安装Xray-TLS+Web"
    fi
    purple "         流程：[更新系统组件]->[安装bbr]->[安装php]->安装Nginx->安装Xray->申请证书->配置文件->[安装/配置Cloudreve]"
    green  "   2. 更新Xray-TLS+Web"
    purple "         流程：更新脚本->[更新系统组件]->[更新bbr]->[更新php]->[更新Nginx]->更新Xray->更新证书->更新配置文件->[更新Cloudreve]"
    tyblue "   3. 检查更新/更新脚本"
    tyblue "   4. 更新系统组件"
    tyblue "   5. 安装/检查更新/更新bbr"
    purple "         包含：bbr2/bbrplus/bbr魔改版/暴力bbr魔改版/锐速"
    tyblue "   6. 安装/检查更新/更新php"
    tyblue "   7. 检查更新/更新Nginx"
    tyblue "   8. 更新Cloudreve"
    tyblue "   9. 更新Xray"
    red    "  10. 卸载Xray-TLS+Web"
    red    "  11. 卸载php"
    red    "  12. 卸载Cloudreve"
    echo
    tyblue " --------------启动/停止-------------"
    tyblue "  13. 启动/重启Xray-TLS+Web"
    tyblue "  14. 停止Xray-TLS+Web"
    echo
    tyblue " ----------------管理----------------"
    tyblue "  15. 查看配置信息"
    tyblue "  16. 重置域名"
    purple "         将删除所有域名配置，安装过程中域名输错了造成Xray无法启动可以用此选项修复"
    tyblue "  17. 添加域名"
    tyblue "  18. 删除域名"
    tyblue "  19. 修改伪装网站类型"
    tyblue "  20. 重新初始化Cloudreve"
    purple "         将删除所有Cloudreve网盘的文件和帐户信息，管理员密码忘记可用此选项恢复"
    tyblue "  21. 修改id(用户ID/UUID)"
    tyblue "  22. 修改path(路径)"
    tyblue "  23. 修改Xray传输协议(TCP/WebSocket)"
    echo
    tyblue " ----------------其它----------------"
    tyblue "  24. 精简系统"
    purple "         删除不必要的系统组件"
    tyblue "  25. 尝试修复退格键无法使用的问题"
    purple "         部分ssh工具(如Xshell)可能有这类问题"
    tyblue "  26. 修改dns"
    yellow "  0. 退出脚本"
    echo
    echo
    local choice=""
    while [[ ! "$choice" =~ ^(0|[1-9][0-9]*)$ ]] || ((choice>26))
    do
        read -p "您的选择是：" choice
    done
    if (( choice==2 || (7<=choice&&choice<=9) || choice==13 || (15<=choice&&choice<=23) )) && [ $is_installed -eq 0 ]; then
        red "请先安装Xray-TLS+Web！！"
        return 1
    fi
    if (( 16<=choice&&choice<=20 )) && ! (systemctl -q is-active nginx && systemctl -q is-active xray); then
        red "请先启动Xray-TLS+Web！！"
        return 1
    fi
    (( 4<=choice&&choice<=6 || choice==24 )) && check_important_dependence_installed lsb-release redhat-lsb-core
    if (( choice==3 || choice==5 || choice==6 || choice==10 )); then
        check_important_dependence_installed ca-certificates ca-certificates
        if [ $choice -eq 10 ]; then
            check_important_dependence_installed curl curl
        else
            check_important_dependence_installed wget wget
        fi
    fi
    (( (4<=choice&&choice<=7) || choice==16 || choice==17 || choice==19 || choice==24 )) && get_system_info
    (( choice==6 || choice==7 || (11<=choice&&choice<=13) || (15<=choice&&choice<=23) )) && get_config_info
    if [ $choice -eq 1 ]; then
        install_update_xray_tls_web
    elif [ $choice -eq 2 ]; then
        update_script && bash "${BASH_SOURCE[0]}" --update
    elif [ $choice -eq 3 ]; then
        if check_script_update; then
            green "脚本可升级！"
            ask_if "是否升级脚本？(y/n)" && update_script && green "脚本更新完成"
        else
            green "脚本已经是最新版本"
        fi
    elif [ $choice -eq 4 ]; then
        doupdate
    elif [ $choice -eq 5 ]; then
        enter_temp_dir
        install_bbr
        $debian_package_manager -y -f install
        rm -rf "$temp_dir"
    elif [ $choice -eq 6 ]; then
        install_check_update_update_php
    elif [ $choice -eq 7 ]; then
        check_update_update_nginx
    elif [ $choice -eq 8 ]; then
        if [ $cloudreve_is_installed -eq 0 ]; then
            red    "请先安装Cloudreve！"
            tyblue "在 修改伪装网站类型/重置域名/添加域名 里选择Cloudreve"
            return 1
        fi
        update_cloudreve
        green "Cloudreve更新完成！"
    elif [ $choice -eq 9 ]; then
        install_update_xray
        green "Xray更新完成！"
    elif [ $choice -eq 10 ]; then
        ! ask_if "确定要删除吗?(y/n)" && return 0
        remove_xray
        remove_nginx
        remove_php
        remove_cloudreve
        $HOME/.acme.sh/acme.sh --uninstall
        rm -rf $HOME/.acme.sh
        green "删除完成！"
    elif [ $choice -eq 11 ]; then
        [ $is_installed -eq 1 ] && check_need_php && red "有域名正在使用php" && return 1
        ! ask_if "确定要删除php吗?(y/n)" && return 0
        remove_php && green "删除完成！"
    elif [ $choice -eq 12 ]; then
        [ $is_installed -eq 1 ] && check_need_cloudreve && red "有域名正在使用Cloudreve" && return 1
        ! ask_if "确定要删除cloudreve吗?(y/n)" && return 0
        remove_cloudreve && green "删除完成！"
    elif [ $choice -eq 13 ]; then
        systemctl restart xray nginx
        turn_on_off_php
        turn_on_off_cloudreve
        sleep 1s
        if ! systemctl -q is-active xray; then
            red "Xray启动失败！！"
        elif ! systemctl -q is-active nginx; then
            red "Nginx启动失败！！"
        elif check_need_php && ! systemctl -q is-active php-fpm; then
            red "php启动失败！！"
        elif check_need_cloudreve && ! systemctl -q is-active cloudreve; then
            red "Cloudreve启动失败！！"
        else
            green "重启/启动成功！！"
        fi
    elif [ $choice -eq 14 ]; then
        systemctl stop xray nginx
        [ $php_is_installed -eq 1 ] && systemctl stop php-fpm
        [ $cloudreve_is_installed -eq 1 ] && systemctl stop cloudreve
        green "已停止！"
    elif [ $choice -eq 15 ]; then
        print_config_info
    elif [ $choice -eq 16 ]; then
        reinit_domain
    elif [ $choice -eq 17 ]; then
        add_domain
    elif [ $choice -eq 18 ]; then
        delete_domain
    elif [ $choice -eq 19 ]; then
        change_pretend
    elif [ $choice -eq 20 ]; then
        reinit_cloudreve
    elif [ $choice -eq 21 ]; then
        change_xray_id
    elif [ $choice -eq 22 ]; then
        change_xray_path
    elif [ $choice -eq 23 ]; then
        change_xray_protocol
    elif [ $choice -eq 24 ]; then
        simplify_system
    elif [ $choice -eq 25 ]; then
        repair_tuige
    elif [ $choice -eq 26 ]; then
        change_dns
    fi
}

if [ "$1" == "--update" ]; then
    update=1
    install_update_xray_tls_web
else
    update=0
    start_menu
fi
