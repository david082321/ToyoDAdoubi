#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS 6+/Debian 6+/Ubuntu 14.04+
#	Description: Install the ShadowsocksR server
#	Version: 2.0.23
#	Author: Toyo
#	Blog: https://doub.io/ss-jc42/
#=================================================

sh_ver="2.0.23"
ssr_folder="/usr/local/shadowsocksr"
ssr_ss_file="${ssr_folder}/shadowsocks"
config_file="${ssr_folder}/config.json"
config_folder="/etc/shadowsocksr"
config_user_file="${config_folder}/user-config.json"
ssr_log_file="${ssr_ss_file}/ssserver.log"
Libsodiumr_file="/usr/local/lib/libsodium.so"
Libsodiumr_ver_backup="1.0.12"
Server_Speeder_file="/serverspeeder/bin/serverSpeeder.sh"
LotServer_file="/appex/bin/serverSpeeder.sh"
BBR_file="${PWD}/bbr.sh"
jq_file="${ssr_folder}/jq"
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[資訊]${Font_color_suffix}"
Error="${Red_font_prefix}[錯誤]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"
Separator_1="——————————————————————————————"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 目前帳號非ROOT(或沒有ROOT權限)，無法繼續操作，請使用${Green_background_prefix} sudo su ${Font_color_suffix}來獲取臨時ROOT權限（執行後會提示輸入目前帳號的密碼）。" && exit 1
}
check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
	bit=`uname -m`
}
check_pid(){
	PID=`ps -ef |grep -v grep | grep server.py |awk '{print $2}'`
}
SSR_installation_status(){
	[[ ! -e ${config_user_file} ]] && echo -e "${Error} 沒有發現 ShadowsocksR 配置文件，請檢查 !" && exit 1
	[[ ! -e ${ssr_folder} ]] && echo -e "${Error} 沒有發現 ShadowsocksR 資料夾，請檢查 !" && exit 1
}
Server_Speeder_installation_status(){
	[[ ! -e ${Server_Speeder_file} ]] && echo -e "${Error} 沒有安裝 銳速(Server Speeder)，請檢查 !" && exit 1
}
LotServer_installation_status(){
	[[ ! -e ${LotServer_file} ]] && echo -e "${Error} 沒有安裝 LotServer，請檢查 !" && exit 1
}
BBR_installation_status(){
	if [[ ! -e ${BBR_file} ]]; then
		echo -e "${Error} 沒有發現 BBR腳本，開始下載..."
		if ! wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/bbr.sh; then
			echo -e "${Error} BBR 腳本下載失敗 !" && exit 1
		else
			echo -e "${Info} BBR 腳本下載完成 !"
			chmod +x bbr.sh
		fi
	fi
}
# 設定 防火牆規則
Add_iptables(){
	iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${ssr_port} -j ACCEPT
	iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${ssr_port} -j ACCEPT
}
Del_iptables(){
	iptables -D INPUT -m state --state NEW -m tcp -p tcp --dport ${port} -j ACCEPT
	iptables -D INPUT -m state --state NEW -m udp -p udp --dport ${port} -j ACCEPT
}
Save_iptables(){
	if [[ ${release} == "centos" ]]; then
		service iptables save
	else
		iptables-save > /etc/iptables.up.rules
	fi
}
Set_iptables(){
	if [[ ${release} == "centos" ]]; then
		service iptables save
		chkconfig --level 2345 iptables on
	elif [[ ${release} == "debian" ]]; then
		iptables-save > /etc/iptables.up.rules
		echo -e '#!/bin/bash\n/sbin/iptables-restore < /etc/iptables.up.rules' > /etc/network/if-pre-up.d/iptables
		chmod +x /etc/network/if-pre-up.d/iptables
	elif [[ ${release} == "ubuntu" ]]; then
		iptables-save > /etc/iptables.up.rules
		echo -e '\npre-up iptables-restore < /etc/iptables.up.rules\npost-down iptables-save > /etc/iptables.up.rules' >> /etc/network/interfaces
		chmod +x /etc/network/interfaces
	fi
}
# 讀取 配置資訊
Get_IP(){
	ip=`wget -qO- -t1 -T2 ipinfo.io/ip`
	[[ -z "$ip" ]] && ip="VPS_IP"
}
Get_User(){
	[[ ! -e ${jq_file} ]] && echo -e "${Error} JQ解析器 不存在，請檢查 !" && exit 1
	port=`${jq_file} '.server_port' ${config_user_file}`
	password=`${jq_file} '.password' ${config_user_file} | sed 's/^.//;s/.$//'`
	method=`${jq_file} '.method' ${config_user_file} | sed 's/^.//;s/.$//'`
	protocol=`${jq_file} '.protocol' ${config_user_file} | sed 's/^.//;s/.$//'`
	obfs=`${jq_file} '.obfs' ${config_user_file} | sed 's/^.//;s/.$//'`
	protocol_param=`${jq_file} '.protocol_param' ${config_user_file} | sed 's/^.//;s/.$//'`
	speed_limit_per_con=`${jq_file} '.speed_limit_per_con' ${config_user_file}`
	speed_limit_per_user=`${jq_file} '.speed_limit_per_user' ${config_user_file}`
	connect_verbose_info=`${jq_file} '.connect_verbose_info' ${config_user_file}`
}
urlsafe_base64(){
	date=$(echo -n "$1"|base64|sed ':a;N;s/\n/ /g;ta'|sed 's/ //g;s/=//g;s/+/-/g;s/\//_/g')
	echo -e "${date}"
}
ss_link_qr(){
	SSbase64=$(urlsafe_base64 "${method}:${password}@${ip}:${port}")
	SSurl="ss://${SSbase64}"
	SSQRcode="http://doub.pw/qr/qr.php?text=${SSurl}"
	ss_link=" SS    鏈接 : ${Green_font_prefix}${SSurl}${Font_color_suffix} \n SS  二維碼 : ${Green_font_prefix}${SSQRcode}${Font_color_suffix}"
}
ssr_link_qr(){
	SSRprotocol=$(echo ${protocol} | sed 's/_compatible//g')
	SSRobfs=$(echo ${obfs} | sed 's/_compatible//g')
	SSRPWDbase64=$(urlsafe_base64 "${password}")
	SSRbase64=$(urlsafe_base64 "${ip}:${port}:${SSRprotocol}:${method}:${SSRobfs}:${SSRPWDbase64}")
	SSRurl="ssr://${SSRbase64}"
	SSRQRcode="http://doub.pw/qr/qr.php?text=${SSRurl}"
	ssr_link=" SSR   鏈接 : ${Red_font_prefix}${SSRurl}${Font_color_suffix} \n SSR 二維碼 : ${Red_font_prefix}${SSRQRcode}${Font_color_suffix} \n "
}
ss_ssr_determine(){
	protocol_suffix=`echo ${protocol} | awk -F "_" '{print $NF}'`
	obfs_suffix=`echo ${obfs} | awk -F "_" '{print $NF}'`
	if [[ ${protocol} = "origin" ]]; then
		if [[ ${obfs} = "plain" ]]; then
			ss_link_qr
			ssr_link=""
		else
			if [[ ${obfs_suffix} != "compatible" ]]; then
				ss_link=""
			else
				ss_link_qr
			fi
		fi
	else
		if [[ ${protocol_suffix} != "compatible" ]]; then
			ss_link=""
		else
			if [[ ${obfs_suffix} != "compatible" ]]; then
				if [[ ${obfs_suffix} = "plain" ]]; then
					ss_link_qr
				else
					ss_link=""
				fi
			else
				ss_link_qr
			fi
		fi
	fi
	ssr_link_qr
}
# 顯示 配置資訊
View_User(){
	SSR_installation_status
	Get_IP
	Get_User
	now_mode=$(cat "${config_user_file}"|grep '"port_password"')
	[[ -z ${protocol_param} ]] && protocol_param="0(無限)"
	if [[ -z "${now_mode}" ]]; then
		ss_ssr_determine
		clear && echo "===================================================" && echo
		echo -e " ShadowsocksR帳號 配置資訊：" && echo
		echo -e " I  P\t    : ${Green_font_prefix}${ip}${Font_color_suffix}"
		echo -e " 端口\t    : ${Green_font_prefix}${port}${Font_color_suffix}"
		echo -e " 密碼\t    : ${Green_font_prefix}${password}${Font_color_suffix}"
		echo -e " 加密\t    : ${Green_font_prefix}${method}${Font_color_suffix}"
		echo -e " 協議\t    : ${Red_font_prefix}${protocol}${Font_color_suffix}"
		echo -e " 混淆\t    : ${Red_font_prefix}${obfs}${Font_color_suffix}"
		echo -e " 設備數限制 : ${Green_font_prefix}${protocol_param}${Font_color_suffix}"
		echo -e " 單線程限速 : ${Green_font_prefix}${speed_limit_per_con} KB/S${Font_color_suffix}"
		echo -e " 端口總限速 : ${Green_font_prefix}${speed_limit_per_user} KB/S${Font_color_suffix}"
		echo -e "${ss_link}"
		echo -e "${ssr_link}"
		echo -e " ${Green_font_prefix} 提示: ${Font_color_suffix}
 在瀏覽器中，打開二維碼鏈接，就可以看到二維碼圖片。
 協議和混淆後面的[ _compatible ]，指的是 兼容原版協議/混淆。"
		echo && echo "==================================================="
	else
		user_total=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | wc -l`
		[[ ${user_total} = "0" ]] && echo -e "${Error} 沒有發現 多端口用戶，請檢查 !" && exit 1
		clear && echo "===================================================" && echo
		echo -e " ShadowsocksR帳號 配置資訊：" && echo
		echo -e " I  P\t    : ${Green_font_prefix}${ip}${Font_color_suffix}"
		echo -e " 加密\t    : ${Green_font_prefix}${method}${Font_color_suffix}"
		echo -e " 協議\t    : ${Red_font_prefix}${protocol}${Font_color_suffix}"
		echo -e " 混淆\t    : ${Red_font_prefix}${obfs}${Font_color_suffix}"
		echo -e " 設備數限制 : ${Green_font_prefix}${protocol_param}${Font_color_suffix}"
		echo -e " 單線程限速 : ${Green_font_prefix}${speed_limit_per_con} KB/S${Font_color_suffix}"
		echo -e " 端口總限速 : ${Green_font_prefix}${speed_limit_per_user} KB/S${Font_color_suffix}" && echo
		for((integer = ${user_total}; integer >= 1; integer--))
		do
			port=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $1}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
			password=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $2}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
			ss_ssr_determine
			echo -e ${Separator_1}
			echo -e " 端口\t    : ${Green_font_prefix}${port}${Font_color_suffix}"
			echo -e " 密碼\t    : ${Green_font_prefix}${password}${Font_color_suffix}"
			echo -e "${ss_link}"
			echo -e "${ssr_link}"
		done
		echo -e " ${Green_font_prefix} 提示: ${Font_color_suffix}
 在瀏覽器中，打開二維碼鏈接，就可以看到二維碼圖片。
 協議和混淆後面的[ _compatible ]，指的是 兼容原版協議/混淆。"
		echo && echo "==================================================="
	fi
}
# 設定 配置資訊
Set_config_port(){
	while true
	do
	echo -e "請輸入要設定的ShadowsocksR帳號 端口"
	stty erase '^H' && read -p "(預設: 2333):" ssr_port
	[[ -z "$ssr_port" ]] && ssr_port="2333"
	expr ${ssr_port} + 0 &>/dev/null
	if [[ $? == 0 ]]; then
		if [[ ${ssr_port} -ge 1 ]] && [[ ${ssr_port} -le 65535 ]]; then
			echo && echo ${Separator_1} && echo -e "	端口 : ${Green_font_prefix}${ssr_port}${Font_color_suffix}" && echo ${Separator_1} && echo
			break
		else
			echo -e "${Error} 請輸入正確的數字(1-65535)"
		fi
	else
		echo -e "${Error} 請輸入正確的數字(1-65535)"
	fi
	done
}
Set_config_password(){
	echo "請輸入要設定的ShadowsocksR帳號 密碼"
	stty erase '^H' && read -p "(預設: doub.io):" ssr_password
	[[ -z "${ssr_password}" ]] && ssr_password="doub.io"
	echo && echo ${Separator_1} && echo -e "	密碼 : ${Green_font_prefix}${ssr_password}${Font_color_suffix}" && echo ${Separator_1} && echo
}
Set_config_method(){
	echo -e "請選擇要設定的ShadowsocksR帳號 加密方式
 ${Green_font_prefix} 1.${Font_color_suffix} none
 ${Tip} 如果使用 auth_chain_a 協議，請加密方式選擇 none，混淆隨意(建議 plain)
 
 ${Green_font_prefix} 2.${Font_color_suffix} rc4
 ${Green_font_prefix} 3.${Font_color_suffix} rc4-md5
 ${Green_font_prefix} 4.${Font_color_suffix} rc4-md5-6
 
 ${Green_font_prefix} 5.${Font_color_suffix} aes-128-ctr
 ${Green_font_prefix} 6.${Font_color_suffix} aes-192-ctr
 ${Green_font_prefix} 7.${Font_color_suffix} aes-256-ctr
 
 ${Green_font_prefix} 8.${Font_color_suffix} aes-128-cfb
 ${Green_font_prefix} 9.${Font_color_suffix} aes-192-cfb
 ${Green_font_prefix}10.${Font_color_suffix} aes-256-cfb
 
 ${Green_font_prefix}11.${Font_color_suffix} aes-128-cfb8
 ${Green_font_prefix}12.${Font_color_suffix} aes-192-cfb8
 ${Green_font_prefix}13.${Font_color_suffix} aes-256-cfb8
 
 ${Green_font_prefix}14.${Font_color_suffix} salsa20
 ${Green_font_prefix}15.${Font_color_suffix} chacha20
 ${Green_font_prefix}16.${Font_color_suffix} chacha20-ietf
 ${Tip} salsa20/chacha20-*系列加密方式，需要額外安裝依賴 libsodium ，否則會無法啟動ShadowsocksR !" && echo
	stty erase '^H' && read -p "(預設: 5. aes-128-ctr):" ssr_method
	[[ -z "${ssr_method}" ]] && ssr_method="5"
	if [[ ${ssr_method} == "1" ]]; then
		ssr_method="none"
	elif [[ ${ssr_method} == "2" ]]; then
		ssr_method="rc4"
	elif [[ ${ssr_method} == "3" ]]; then
		ssr_method="rc4-md5"
	elif [[ ${ssr_method} == "4" ]]; then
		ssr_method="rc4-md5-6"
	elif [[ ${ssr_method} == "5" ]]; then
		ssr_method="aes-128-ctr"
	elif [[ ${ssr_method} == "6" ]]; then
		ssr_method="aes-192-ctr"
	elif [[ ${ssr_method} == "7" ]]; then
		ssr_method="aes-256-ctr"
	elif [[ ${ssr_method} == "8" ]]; then
		ssr_method="aes-128-cfb"
	elif [[ ${ssr_method} == "9" ]]; then
		ssr_method="aes-192-cfb"
	elif [[ ${ssr_method} == "10" ]]; then
		ssr_method="aes-256-cfb"
	elif [[ ${ssr_method} == "11" ]]; then
		ssr_method="aes-128-cfb8"
	elif [[ ${ssr_method} == "12" ]]; then
		ssr_method="aes-192-cfb8"
	elif [[ ${ssr_method} == "13" ]]; then
		ssr_method="aes-256-cfb8"
	elif [[ ${ssr_method} == "14" ]]; then
		ssr_method="salsa20"
	elif [[ ${ssr_method} == "15" ]]; then
		ssr_method="chacha20"
	elif [[ ${ssr_method} == "16" ]]; then
		ssr_method="chacha20-ietf"
	else
		ssr_method="aes-128-ctr"
	fi
	echo && echo ${Separator_1} && echo -e "	加密 : ${Green_font_prefix}${ssr_method}${Font_color_suffix}" && echo ${Separator_1} && echo
}
Set_config_protocol(){
	echo -e "請選擇要設定的ShadowsocksR帳號 協議插件
 ${Green_font_prefix}1.${Font_color_suffix} origin
 ${Green_font_prefix}2.${Font_color_suffix} auth_sha1_v4
 ${Green_font_prefix}3.${Font_color_suffix} auth_aes128_md5
 ${Green_font_prefix}4.${Font_color_suffix} auth_aes128_sha1
 ${Green_font_prefix}5.${Font_color_suffix} auth_chain_a
 ${Green_font_prefix}6.${Font_color_suffix} auth_chain_b
 ${Tip} 如果使用 auth_chain_a 協議，請加密方式選擇 none，混淆隨意(建議 plain)" && echo
	stty erase '^H' && read -p "(預設: 2. auth_sha1_v4):" ssr_protocol
	[[ -z "${ssr_protocol}" ]] && ssr_protocol="2"
	if [[ ${ssr_protocol} == "1" ]]; then
		ssr_protocol="origin"
	elif [[ ${ssr_protocol} == "2" ]]; then
		ssr_protocol="auth_sha1_v4"
	elif [[ ${ssr_protocol} == "3" ]]; then
		ssr_protocol="auth_aes128_md5"
	elif [[ ${ssr_protocol} == "4" ]]; then
		ssr_protocol="auth_aes128_sha1"
	elif [[ ${ssr_protocol} == "5" ]]; then
		ssr_protocol="auth_chain_a"
	elif [[ ${ssr_protocol} == "6" ]]; then
		ssr_protocol="auth_chain_b"
	else
		ssr_protocol="auth_sha1_v4"
	fi
	echo && echo ${Separator_1} && echo -e "	協議 : ${Green_font_prefix}${ssr_protocol}${Font_color_suffix}" && echo ${Separator_1} && echo
	if [[ ${ssr_protocol} != "origin" ]]; then
		if [[ ${ssr_protocol} == "auth_sha1_v4" ]]; then
			stty erase '^H' && read -p "是否設定 協議插件兼容原版(_compatible)？[Y/n]" ssr_protocol_yn
			[[ -z "${ssr_protocol_yn}" ]] && ssr_protocol_yn="y"
			[[ $ssr_protocol_yn == [Yy] ]] && ssr_protocol=${ssr_protocol}"_compatible"
			echo
		fi
	fi
}
Set_config_obfs(){
	echo -e "請選擇要設定的ShadowsocksR帳號 混淆插件
 ${Green_font_prefix}1.${Font_color_suffix} plain
 ${Green_font_prefix}2.${Font_color_suffix} http_simple
 ${Green_font_prefix}3.${Font_color_suffix} http_post
 ${Green_font_prefix}4.${Font_color_suffix} random_head
 ${Green_font_prefix}5.${Font_color_suffix} tls1.2_ticket_auth
 ${Tip} 如果使用 ShadowsocksR 加速遊戲，請選擇 混淆兼容原版或 plain 混淆，然後客戶端選擇 plain，否則會增加延遲 !" && echo
	stty erase '^H' && read -p "(預設: 5. tls1.2_ticket_auth):" ssr_obfs
	[[ -z "${ssr_obfs}" ]] && ssr_obfs="5"
	if [[ ${ssr_obfs} == "1" ]]; then
		ssr_obfs="plain"
	elif [[ ${ssr_obfs} == "2" ]]; then
		ssr_obfs="http_simple"
	elif [[ ${ssr_obfs} == "3" ]]; then
		ssr_obfs="http_post"
	elif [[ ${ssr_obfs} == "4" ]]; then
		ssr_obfs="random_head"
	elif [[ ${ssr_obfs} == "5" ]]; then
		ssr_obfs="tls1.2_ticket_auth"
	else
		ssr_obfs="tls1.2_ticket_auth"
	fi
	echo && echo ${Separator_1} && echo -e "	混淆 : ${Green_font_prefix}${ssr_obfs}${Font_color_suffix}" && echo ${Separator_1} && echo
	if [[ ${ssr_obfs} != "plain" ]]; then
			stty erase '^H' && read -p "是否設定 混淆插件兼容原版(_compatible)？[Y/n]" ssr_obfs_yn
			[[ -z "${ssr_obfs_yn}" ]] && ssr_obfs_yn="y"
			[[ $ssr_obfs_yn == [Yy] ]] && ssr_obfs=${ssr_obfs}"_compatible"
			echo
	fi
}
Set_config_protocol_param(){
	while true
	do
	echo -e "請輸入要設定的ShadowsocksR帳號 欲限制的設備數 (${Green_font_prefix} auth_* 系列協議 不兼容原版才有效 ${Font_color_suffix})"
	echo -e "${Tip} 設備數限制：每個端口同一時間能鏈接的客戶端數量(多端口模式，每個端口都是獨立計算)，建議最少 2個。"
	stty erase '^H' && read -p "(預設: 無限):" ssr_protocol_param
	[[ -z "$ssr_protocol_param" ]] && ssr_protocol_param="" && echo && break
	expr ${ssr_protocol_param} + 0 &>/dev/null
	if [[ $? == 0 ]]; then
		if [[ ${ssr_protocol_param} -ge 1 ]] && [[ ${ssr_protocol_param} -le 9999 ]]; then
			echo && echo ${Separator_1} && echo -e "	設備數限制 : ${Green_font_prefix}${ssr_protocol_param}${Font_color_suffix}" && echo ${Separator_1} && echo
			break
		else
			echo -e "${Error} 請輸入正確的數字(1-9999)"
		fi
	else
		echo -e "${Error} 請輸入正確的數字(1-9999)"
	fi
	done
}
Set_config_speed_limit_per_con(){
	while true
	do
	echo -e "請輸入要設定的每個端口 單線程 限速上限(單位：KB/S)"
	echo -e "${Tip} 單線程限速：每個端口 單線程的限速上限，多線程即無效。"
	stty erase '^H' && read -p "(預設: 無限):" ssr_speed_limit_per_con
	[[ -z "$ssr_speed_limit_per_con" ]] && ssr_speed_limit_per_con=0 && echo && break
	expr ${ssr_speed_limit_per_con} + 0 &>/dev/null
	if [[ $? == 0 ]]; then
		if [[ ${ssr_speed_limit_per_con} -ge 1 ]] && [[ ${ssr_speed_limit_per_con} -le 131072 ]]; then
			echo && echo ${Separator_1} && echo -e "	單線程限速 : ${Green_font_prefix}${ssr_speed_limit_per_con} KB/S${Font_color_suffix}" && echo ${Separator_1} && echo
			break
		else
			echo -e "${Error} 請輸入正確的數字(1-131072)"
		fi
	else
		echo -e "${Error} 請輸入正確的數字(1-131072)"
	fi
	done
}
Set_config_speed_limit_per_user(){
	while true
	do
	echo
	echo -e "請輸入要設定的每個端口 總速度 限速上限(單位：KB/S)"
	echo -e "${Tip} 端口總限速：每個端口 總速度 限速上限，單個端口整體限速。"
	stty erase '^H' && read -p "(預設: 無限):" ssr_speed_limit_per_user
	[[ -z "$ssr_speed_limit_per_user" ]] && ssr_speed_limit_per_user=0 && echo && break
	expr ${ssr_speed_limit_per_user} + 0 &>/dev/null
	if [[ $? == 0 ]]; then
		if [[ ${ssr_speed_limit_per_user} -ge 1 ]] && [[ ${ssr_speed_limit_per_user} -le 131072 ]]; then
			echo && echo ${Separator_1} && echo -e "	端口總限速 : ${Green_font_prefix}${ssr_speed_limit_per_user} KB/S${Font_color_suffix}" && echo ${Separator_1} && echo
			break
		else
			echo -e "${Error} 請輸入正確的數字(1-131072)"
		fi
	else
		echo -e "${Error} 請輸入正確的數字(1-131072)"
	fi
	done
}
Set_config_all(){
	Set_config_port
	Set_config_password
	Set_config_method
	Set_config_protocol
	Set_config_obfs
	Set_config_protocol_param
	Set_config_speed_limit_per_con
	Set_config_speed_limit_per_user
}
# 修改 配置資訊
Modify_config_port(){
	sed -i 's/"server_port": '"$(echo ${port})"'/"server_port": '"$(echo ${ssr_port})"'/g' ${config_user_file}
}
Modify_config_password(){
	sed -i 's/"password": "'"$(echo ${password})"'"/"password": "'"$(echo ${ssr_password})"'"/g' ${config_user_file}
}
Modify_config_method(){
	sed -i 's/"method": "'"$(echo ${method})"'"/"method": "'"$(echo ${ssr_method})"'"/g' ${config_user_file}
}
Modify_config_protocol(){
	sed -i 's/"protocol": "'"$(echo ${protocol})"'"/"protocol": "'"$(echo ${ssr_protocol})"'"/g' ${config_user_file}
}
Modify_config_obfs(){
	sed -i 's/"obfs": "'"$(echo ${obfs})"'"/"obfs": "'"$(echo ${ssr_obfs})"'"/g' ${config_user_file}
}
Modify_config_protocol_param(){
	sed -i 's/"protocol_param": "'"$(echo ${protocol_param})"'"/"protocol_param": "'"$(echo ${ssr_protocol_param})"'"/g' ${config_user_file}
}
Modify_config_speed_limit_per_con(){
	sed -i 's/"speed_limit_per_con": '"$(echo ${speed_limit_per_con})"'/"speed_limit_per_con": '"$(echo ${ssr_speed_limit_per_con})"'/g' ${config_user_file}
}
Modify_config_speed_limit_per_user(){
	sed -i 's/"speed_limit_per_user": '"$(echo ${speed_limit_per_user})"'/"speed_limit_per_user": '"$(echo ${ssr_speed_limit_per_user})"'/g' ${config_user_file}
}
Modify_config_connect_verbose_info(){
	sed -i 's/"connect_verbose_info": '"$(echo ${connect_verbose_info})"'/"connect_verbose_info": '"$(echo ${ssr_connect_verbose_info})"'/g' ${config_user_file}
}
Modify_config_all(){
	Modify_config_port
	Modify_config_password
	Modify_config_method
	Modify_config_protocol
	Modify_config_obfs
	Modify_config_protocol_param
	Modify_config_speed_limit_per_con
	Modify_config_speed_limit_per_user
}
Modify_config_port_many(){
	sed -i 's/"'"$(echo ${port})"'":/"'"$(echo ${ssr_port})"'":/g' ${config_user_file}
}
Modify_config_password_many(){
	sed -i 's/"'"$(echo ${password})"'"/"'"$(echo ${ssr_password})"'"/g' ${config_user_file}
}
# 寫入 配置資訊
Write_configuration(){
	cat > ${config_user_file}<<-EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": ${ssr_port},
    "local_address": "127.0.0.1",
    "local_port": 1080,

    "password": "${ssr_password}",
    "method": "${ssr_method}",
    "protocol": "${ssr_protocol}",
    "protocol_param": "${ssr_protocol_param}",
    "obfs": "${ssr_obfs}",
    "obfs_param": "",
    "speed_limit_per_con": ${ssr_speed_limit_per_con},
    "speed_limit_per_user": ${ssr_speed_limit_per_user},

    "additional_ports" : {},
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": false
}
EOF
}
Write_configuration_many(){
	cat > ${config_user_file}<<-EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "local_address": "127.0.0.1",
    "local_port": 1080,

    "port_password":{
        "${ssr_port}":"${ssr_password}"
    },
    "method": "${ssr_method}",
    "protocol": "${ssr_protocol}",
    "protocol_param": "${ssr_protocol_param}",
    "obfs": "${ssr_obfs}",
    "obfs_param": "",
    "speed_limit_per_con": ${ssr_speed_limit_per_con},
    "speed_limit_per_user": ${ssr_speed_limit_per_user},

    "additional_ports" : {},
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": false
}
EOF
}
Check_python(){
	python_ver=`python -h`
	if [[ -z ${python_ver} ]]; then
		echo -e "${Info} 沒有安裝Python，開始安裝..."
		if [[ ${release} == "centos" ]]; then
			yum install -y python
		else
			apt-get install -y python
		fi
	fi
}
Centos_yum(){
	yum update
	yum install -y vim git
}
Debian_apt(){
	apt-get update
	apt-get install -y vim git
}
# 下載 ShadowsocksR
Download_SSR(){
	cd "/usr/local"
	#git config --global http.sslVerify false
	env GIT_SSL_NO_VERIFY=true git clone -b manyuser https://github.com/ToyoDAdoubi/shadowsocksr.git
	[[ ! -e ${ssr_folder} ]] && echo -e "${Error} ShadowsocksR服務端 下載失敗 !" && exit 1
	[[ -e ${config_folder} ]] && rm -rf ${config_folder}
	mkdir ${config_folder}
	[[ ! -e ${config_folder} ]] && echo -e "${Error} ShadowsocksR配置文件的資料夾 建立失敗 !" && exit 1
	echo -e "${Info} ShadowsocksR服務端 下載完成 !"
}
Service_SSR(){
	if [[ ${release} = "centos" ]]; then
		if ! wget --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/other/ssr_centos -O /etc/init.d/ssr; then
			echo -e "${Error} ShadowsocksR服務 管理腳本下載失敗 !" && exit 1
		fi
		chmod +x /etc/init.d/ssr
		chkconfig --add ssr
		chkconfig ssr on
	else
		if ! wget --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/other/ssr_debian -O /etc/init.d/ssr; then
			echo -e "${Error} ShadowsocksR服務 管理腳本下載失敗 !" && exit 1
		fi
		chmod +x /etc/init.d/ssr
		update-rc.d -f ssr defaults
	fi
	echo -e "${Info} ShadowsocksR服務 管理腳本下載完成 !"
}
# 安裝 JQ解析器
JQ_install(){
	if [[ ! -e ${jq_file} ]]; then
		if [[ ${bit} = "x86_64" ]]; then
			wget --no-check-certificate "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64" -O ${jq_file}
		else
			wget --no-check-certificate "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux32" -O ${jq_file}
		fi
		[[ ! -e ${jq_file} ]] && echo -e "${Error} JQ解析器 下載失敗，請檢查 !" && exit 1
		chmod +x ${jq_file}
		echo -e "${Info} JQ解析器 安裝完成，繼續..." 
	else
		echo -e "${Info} JQ解析器 已安裝，繼續..."
	fi
}
# 安裝 依賴
Installation_dependency(){
	if [[ ${release} == "centos" ]]; then
		Centos_yum
	else
		Debian_apt
	fi
	[[ ! -e "/usr/bin/git" ]] && echo -e "${Error} 依賴 Git 安裝失敗，多半是軟件包源的問題，請檢查 !" && exit 1
	Check_python
	echo "nameserver 8.8.8.8" > /etc/resolv.conf
	echo "nameserver 8.8.4.4" >> /etc/resolv.conf
	cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}
Install_SSR(){
	check_root
	[[ -e ${config_user_file} ]] && echo -e "${Error} ShadowsocksR 配置文件已存在，請檢查( 如安裝失敗或者存在舊版本，請先卸載 ) !" && exit 1
	[[ -e ${ssr_folder} ]] && echo -e "${Error} ShadowsocksR 資料夾已存在，請檢查( 如安裝失敗或者存在舊版本，請先卸載 ) !" && exit 1
	echo -e "${Info} 開始設定 ShadowsocksR帳號配置..."
	Set_config_all
	echo -e "${Info} 開始安裝/配置 ShadowsocksR依賴..."
	Installation_dependency
	echo -e "${Info} 開始下載/安裝 ShadowsocksR文件..."
	Download_SSR
	echo -e "${Info} 開始下載/安裝 ShadowsocksR服務腳本(init)..."
	Service_SSR
	echo -e "${Info} 開始下載/安裝 JSNO解析器 JQ..."
	JQ_install
	echo -e "${Info} 開始寫入 ShadowsocksR配置文件..."
	Write_configuration
	echo -e "${Info} 開始設定 iptables防火牆..."
	Set_iptables
	echo -e "${Info} 開始添加 iptables防火牆規則..."
	Add_iptables
	echo -e "${Info} 開始儲存 iptables防火牆規則..."
	Save_iptables
	echo -e "${Info} 所有步驟 安裝完畢，開始啟動 ShadowsocksR服務端..."
	Start_SSR
}
Update_SSR(){
	SSR_installation_status
	echo -e "因破娃暫停更新ShadowsocksR服務端，所以此功能臨時禁用。"
	#cd ${ssr_folder}
	#git pull
	#Restart_SSR
}
Uninstall_SSR(){
	[[ ! -e ${config_user_file} ]] && [[ ! -e ${ssr_folder} ]] && echo -e "${Error} 沒有安裝 ShadowsocksR，請檢查 !" && exit 1
	echo "確定要 卸載ShadowsocksR？[y/N]" && echo
	stty erase '^H' && read -p "(預設: n):" unyn
	[[ -z ${unyn} ]] && unyn="n"
	if [[ ${unyn} == [Yy] ]]; then
		check_pid
		[[ ! -z "${PID}" ]] && kill -9 ${PID}
		if [[ -z "${now_mode}" ]]; then
			port=`${jq_file} '.server_port' ${config_user_file}`
			Del_iptables
		else
			user_total=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | wc -l`
			for((integer = 1; integer <= ${user_total}; integer++))
			do
				port=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $1}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
				Del_iptables
			done
		fi
		if [[ ${release} = "centos" ]]; then
			chkconfig --del ssr
		else
			update-rc.d -f ssr remove
		fi
		rm -rf ${ssr_folder} && rm -rf ${config_folder} && rm -rf /etc/init.d/ssr
		echo && echo " ShadowsocksR 卸載完成 !" && echo
	else
		echo && echo " 卸載已取消..." && echo
	fi
}
Check_Libsodium_ver(){
	echo -e "${Info} 開始獲取 libsodium 最新版本..."
	Libsodiumr_ver=`wget -qO- https://github.com/jedisct1/libsodium/releases/latest | grep "<title>" | sed -r 's/.*Release (.+) · jedisct1.*/\1/'`
	[[ -z ${Libsodiumr_ver} ]] && Libsodiumr_ver=${Libsodiumr_ver_backup}
	echo -e "${Info} libsodium 最新版本為 ${Green_font_prefix}${Libsodiumr_ver}${Font_color_suffix} !"
}
Install_Libsodium(){
	[[ -e ${Libsodiumr_file} ]] && echo -e "${Error} libsodium 已安裝 !" && exit 1
	echo -e "${Info} libsodium 未安裝，開始安裝..."
	Check_Libsodium_ver
	if [[ ${release} == "centos" ]]; then
		yum update
		yum -y groupinstall "Development Tools"
		wget  --no-check-certificate -N https://github.com/jedisct1/libsodium/releases/download/${Libsodiumr_ver}/libsodium-${Libsodiumr_ver}.tar.gz
		tar -xzf libsodium-${Libsodiumr_ver}.tar.gz && cd libsodium-${Libsodiumr_ver}
		./configure --disable-maintainer-mode && make -j2 && make install
		echo /usr/local/lib > /etc/ld.so.conf.d/usr_local_lib.conf
	else
		apt-get update
		apt-get install -y build-essential
		wget  --no-check-certificate -N https://github.com/jedisct1/libsodium/releases/download/${Libsodiumr_ver}/libsodium-${Libsodiumr_ver}.tar.gz
		tar -xzf libsodium-${Libsodiumr_ver}.tar.gz && cd libsodium-${Libsodiumr_ver}
		./configure --disable-maintainer-mode && make -j2 && make install
	fi
	ldconfig
	cd .. && rm -rf libsodium-${Libsodiumr_ver}.tar.gz && rm -rf libsodium-${Libsodiumr_ver}
	[[ ! -e ${Libsodiumr_file} ]] && echo -e "${Error} libsodium 安裝失敗 !" && exit 1
	echo && echo -e "${Info} libsodium 安裝成功 !" && echo
}
# 顯示 連接資訊
debian_View_user_connection_info(){
	if [[ -z "${now_mode}" ]]; then
		now_mode="單端口" && user_total="1"
		IP_total=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp6' |awk '{print $5}' |awk -F ":" '{print $1}' |sort -u |wc -l`
		user_port=`${jq_file} '.server_port' ${config_user_file}`
		user_IP=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp6' |grep "${user_port}" |awk '{print $5}' |awk -F ":" '{print $1}' |sort -u`
		if [[ -z ${user_IP} ]]; then
			user_IP_total="0"
		else
			user_IP_total=`echo -e "${user_IP}"|wc -l`
			user_IP=`echo ${user_IP}|sed 's/ / | /g'`
		fi
		user_list_all="端口: ${Green_font_prefix}"${user_port}"${Font_color_suffix}, 鏈接IP總數: ${Green_font_prefix}"${user_IP_total}"${Font_color_suffix}, 目前鏈接IP: ${Green_font_prefix}"${user_IP}"${Font_color_suffix}\n"
		echo -e "目前模式: ${Green_background_prefix} "${now_mode}" ${Font_color_suffix}，鏈接IP總數: ${Green_background_prefix} "${IP_total}" ${Font_color_suffix}"
		echo -e ${user_list_all}
	else
		now_mode="多端口" && user_total=`${jq_file} '.port_password' ${config_user_file} |sed '$d;1d' | wc -l`
		IP_total=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp6' |awk '{print $5}' |awk -F ":" '{print $1}' |sort -u |wc -l`
		user_list_all=""
		for((integer = ${user_total}; integer >= 1; integer--))
		do
			user_port=`${jq_file} '.port_password' ${config_user_file} |sed '$d;1d' |awk -F ":" '{print $1}' |sed -n "${integer}p" |sed -r 's/.*\"(.+)\".*/\1/'`
			user_IP=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp6' |grep "${user_port}" |awk '{print $5}' |awk -F ":" '{print $1}' |sort -u`
			if [[ -z ${user_IP} ]]; then
				user_IP_total="0"
			else
				user_IP_total=`echo -e "${user_IP}"|wc -l`
				user_IP=`echo ${user_IP}|sed 's/ / | /g'`
			fi
			user_list_all=${user_list_all}"端口: ${Green_font_prefix}"${user_port}"${Font_color_suffix}, 鏈接IP總數: ${Green_font_prefix}"${user_IP_total}"${Font_color_suffix}, 目前鏈接IP: ${Green_font_prefix}"${user_IP}"${Font_color_suffix}\n"
		done
		echo -e "目前模式: ${Green_background_prefix} "${now_mode}" ${Font_color_suffix} ，用戶總數: ${Green_background_prefix} "${user_total}" ${Font_color_suffix} ，鏈接IP總數: ${Green_background_prefix} "${IP_total}" ${Font_color_suffix} "
		echo -e ${user_list_all}
	fi
}
centos_View_user_connection_info(){
	if [[ -z "${now_mode}" ]]; then
		now_mode="單端口" && user_total="1"
		IP_total=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp' |grep '::ffff:' |awk '{print $5}' |awk -F ":" '{print $4}' |sort -u |wc -l`
		user_port=`${jq_file} '.server_port' ${config_user_file}`
		user_IP=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp' |grep "${user_port}" | grep '::ffff:' |awk '{print $5}' |awk -F ":" '{print $4}' |sort -u`
		if [[ -z ${user_IP} ]]; then
			user_IP_total="0"
		else
			user_IP_total=`echo -e "${user_IP}"|wc -l`
			user_IP=`echo ${user_IP}|sed 's/ / | /g'`
		fi
		user_list_all="端口: ${Green_font_prefix}"${user_port}"${Font_color_suffix}, 鏈接IP總數: ${Green_font_prefix}"${user_IP_total}"${Font_color_suffix}, 目前鏈接IP: ${Green_font_prefix}"${user_IP}"${Font_color_suffix}\n"
		echo -e "目前模式: ${Green_background_prefix} "${now_mode}" ${Font_color_suffix}，鏈接IP總數: ${Green_background_prefix} "${IP_total}" ${Font_color_suffix}"
		echo -e ${user_list_all}
	else
		now_mode="多端口" && user_total=`${jq_file} '.port_password' ${config_user_file} |sed '$d;1d' | wc -l`
		IP_total=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp' | grep '::ffff:' |awk '{print $5}' |awk -F ":" '{print $4}' |sort -u |wc -l`
		user_list_all=""
		for((integer = 1; integer <= ${user_total}; integer++))
		do
			user_port=`${jq_file} '.port_password' ${config_user_file} |sed '$d;1d' |awk -F ":" '{print $1}' |sed -n "${integer}p" |sed -r 's/.*\"(.+)\".*/\1/'`
			user_IP=`netstat -anp |grep 'ESTABLISHED' |grep 'python' |grep 'tcp' |grep "${user_port}"|grep '::ffff:' |awk '{print $5}' |awk -F ":" '{print $4}' |sort -u`
			if [[ -z ${user_IP} ]]; then
				user_IP_total="0"
			else
				user_IP_total=`echo -e "${user_IP}"|wc -l`
				user_IP=`echo ${user_IP}|sed 's/ / | /g'`
			fi
			user_list_all=${user_list_all}"端口: ${Green_font_prefix}"${user_port}"${Font_color_suffix}, 鏈接IP總數: ${Green_font_prefix}"${user_IP_total}"${Font_color_suffix}, 目前鏈接IP: ${Green_font_prefix}"${user_IP}"${Font_color_suffix}\n"
		done
		echo -e "目前模式: ${Green_background_prefix} "${now_mode}" ${Font_color_suffix} ，用戶總數: ${Green_background_prefix} "${user_total}" ${Font_color_suffix} ，鏈接IP總數: ${Green_background_prefix} "${IP_total}" ${Font_color_suffix} "
		echo -e ${user_list_all}
	fi
}
View_user_connection_info(){
	SSR_installation_status
	if [[ ${release} = "centos" ]]; then
		cat /etc/redhat-release |grep 7\..*|grep -i centos>/dev/null
		if [[ $? = 0 ]]; then
			debian_View_user_connection_info
		else
			centos_View_user_connection_info
		fi
	else
		debian_View_user_connection_info
	fi
}
# 修改 用戶配置
Modify_Config(){
	SSR_installation_status
	if [[ -z "${now_mode}" ]]; then
		echo && echo -e "目前模式: 單端口，你要做什麼？
 ${Green_font_prefix}1.${Font_color_suffix} 修改 用戶端口
 ${Green_font_prefix}2.${Font_color_suffix} 修改 用戶密碼
 ${Green_font_prefix}3.${Font_color_suffix} 修改 加密方式
 ${Green_font_prefix}4.${Font_color_suffix} 修改 協議插件
 ${Green_font_prefix}5.${Font_color_suffix} 修改 混淆插件
 ${Green_font_prefix}6.${Font_color_suffix} 修改 設備數限制
 ${Green_font_prefix}7.${Font_color_suffix} 修改 單線程限速
 ${Green_font_prefix}8.${Font_color_suffix} 修改 端口總限速
 ${Green_font_prefix}9.${Font_color_suffix} 修改 全部配置" && echo
		stty erase '^H' && read -p "(預設: 取消):" ssr_modify
		[[ -z "${ssr_modify}" ]] && echo "已取消..." && exit 1
		Get_User
		if [[ ${ssr_modify} == "1" ]]; then
			Set_config_port
			Modify_config_port
			Add_iptables
			Del_iptables
			Save_iptables
		elif [[ ${ssr_modify} == "2" ]]; then
			Set_config_password
			Modify_config_password
		elif [[ ${ssr_modify} == "3" ]]; then
			Set_config_method
			Modify_config_method
		elif [[ ${ssr_modify} == "4" ]]; then
			Set_config_protocol
			Modify_config_protocol
		elif [[ ${ssr_modify} == "5" ]]; then
			Set_config_obfs
			Modify_config_obfs
		elif [[ ${ssr_modify} == "6" ]]; then
			Set_config_protocol_param
			Modify_config_protocol_param
		elif [[ ${ssr_modify} == "7" ]]; then
			Set_config_speed_limit_per_con
			Modify_config_speed_limit_per_con
		elif [[ ${ssr_modify} == "8" ]]; then
			Set_config_speed_limit_per_user
			Modify_config_speed_limit_per_user
		elif [[ ${ssr_modify} == "9" ]]; then
			Set_config_all
			Modify_config_all
		else
			echo -e "${Error} 請輸入正確的數字(1-9)" && exit 1
		fi
	else
		echo && echo -e "目前模式: 多端口，你要做什麼？
 ${Green_font_prefix}1.${Font_color_suffix} 添加 用戶配置
 ${Green_font_prefix}2.${Font_color_suffix} 刪除 用戶配置
 ${Green_font_prefix}3.${Font_color_suffix} 修改 用戶配置
——————————
 ${Green_font_prefix}4.${Font_color_suffix} 修改 加密方式
 ${Green_font_prefix}5.${Font_color_suffix} 修改 協議插件
 ${Green_font_prefix}6.${Font_color_suffix} 修改 混淆插件
 ${Green_font_prefix}7.${Font_color_suffix} 修改 設備數限制
 ${Green_font_prefix}8.${Font_color_suffix} 修改 單線程限速
 ${Green_font_prefix}9.${Font_color_suffix} 修改 端口總限速
 ${Green_font_prefix}10.${Font_color_suffix} 修改 全部配置" && echo
		stty erase '^H' && read -p "(預設: 取消):" ssr_modify
		[[ -z "${ssr_modify}" ]] && echo "已取消..." && exit 1
		Get_User
		if [[ ${ssr_modify} == "1" ]]; then
			Add_multi_port_user
		elif [[ ${ssr_modify} == "2" ]]; then
			Del_multi_port_user
		elif [[ ${ssr_modify} == "3" ]]; then
			Modify_multi_port_user
		elif [[ ${ssr_modify} == "4" ]]; then
			Set_config_method
			Modify_config_method
		elif [[ ${ssr_modify} == "5" ]]; then
			Set_config_protocol
			Modify_config_protocol
		elif [[ ${ssr_modify} == "6" ]]; then
			Set_config_obfs
			Modify_config_obfs
		elif [[ ${ssr_modify} == "7" ]]; then
			Set_config_protocol_param
			Modify_config_protocol_param
		elif [[ ${ssr_modify} == "8" ]]; then
			Set_config_speed_limit_per_con
			Modify_config_speed_limit_per_con
		elif [[ ${ssr_modify} == "9" ]]; then
			Set_config_speed_limit_per_user
			Modify_config_speed_limit_per_user
		elif [[ ${ssr_modify} == "10" ]]; then
			Set_config_method
			Set_config_protocol
			Set_config_obfs
			Set_config_protocol_param
			Set_config_speed_limit_per_con
			Set_config_speed_limit_per_user
			Modify_config_method
			Modify_config_protocol
			Modify_config_obfs
			Modify_config_protocol_param
			Modify_config_speed_limit_per_con
			Modify_config_speed_limit_per_user
		else
			echo -e "${Error} 請輸入正確的數字(1-9)" && exit 1
		fi
	fi
	Restart_SSR
}
# 顯示 多端口用戶配置
List_multi_port_user(){
	user_total=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | wc -l`
	[[ ${user_total} = "0" ]] && echo -e "${Error} 沒有發現 多端口用戶，請檢查 !" && exit 1
	user_list_all=""
	for((integer = ${user_total}; integer >= 1; integer--))
	do
		user_port=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $1}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
		user_password=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $2}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
		user_list_all=${user_list_all}"端口: "${user_port}" 密碼: "${user_password}"\n"
	done
	echo && echo -e "用戶總數 ${Green_font_prefix}"${user_total}"${Font_color_suffix}"
	echo -e ${user_list_all}
}
# 添加 多端口用戶配置
Add_multi_port_user(){
	Set_config_port
	Set_config_password
	sed -i "8 i \"        \"${ssr_port}\":\"${ssr_password}\"," ${config_user_file}
	sed -i "8s/^\"//" ${config_user_file}
	Add_iptables
	Save_iptables
	echo -e "${Info} 多端口用戶添加完成 ${Green_font_prefix}[端口: ${ssr_port} , 密碼: ${ssr_password}]${Font_color_suffix} "
}
# 修改 多端口用戶配置
Modify_multi_port_user(){
	List_multi_port_user
	echo && echo -e "請輸入要修改的用戶端口"
	stty erase '^H' && read -p "(預設: 取消):" modify_user_port
	[[ -z "${modify_user_port}" ]] && echo -e "已取消..." && exit 1
	del_user=`cat ${config_user_file}|grep '"'"${modify_user_port}"'"'`
	if [[ ! -z "${del_user}" ]]; then
		port="${modify_user_port}"
		password=`echo -e ${del_user}|awk -F ":" '{print $NF}'|sed -r 's/.*\"(.+)\".*/\1/'`
		Set_config_port
		Set_config_password
		sed -i 's/"'$(echo ${port})'":"'$(echo ${password})'"/"'$(echo ${ssr_port})'":"'$(echo ${ssr_password})'"/g' ${config_user_file}
		Del_iptables
		Add_iptables
		Save_iptables
		echo -e "${Inof} 多端口用戶修改完成 ${Green_font_prefix}[舊: ${modify_user_port}  ${password} , 新: ${ssr_port}  ${ssr_password}]${Font_color_suffix} "
	else
		echo -e "${Error} 請輸入正確的端口 !" && exit 1
	fi
}
# 刪除 多端口用戶配置
Del_multi_port_user(){
	List_multi_port_user
	user_total=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | wc -l`
	[[ "${user_total}" = "1" ]] && echo -e "${Error} 多端口用戶僅剩 1個，不能刪除 !" && exit 1
	echo -e "請輸入要刪除的用戶端口"
	stty erase '^H' && read -p "(預設: 取消):" del_user_port
	[[ -z "${del_user_port}" ]] && echo -e "已取消..." && exit 1
	del_user=`cat ${config_user_file}|grep '"'"${del_user_port}"'"'`
	if [[ ! -z ${del_user} ]]; then
		port=${del_user_port}
		Del_iptables
		Save_iptables
		del_user_determine=`echo ${del_user:((${#del_user} - 1))}`
		if [[ ${del_user_determine} != "," ]]; then
			del_user_num=$(sed -n -e "/${port}/=" ${config_user_file})
			del_user_num=$(expr $del_user_num - 1)
			sed -i "${del_user_num}s/,//g" ${config_user_file}
		fi
		sed -i "/${port}/d" ${config_user_file}
		echo -e "${Info} 多端口用戶刪除完成 ${Green_font_prefix} ${del_user_port} ${Font_color_suffix} "
	else
		echo "${Error} 請輸入正確的端口 !" && exit 1
	fi
}
# 手動修改 用戶配置
Manually_Modify_Config(){
	SSR_installation_status
	port=`${jq_file} '.server_port' ${config_user_file}`
	vi ${config_user_file}
	if [[ -z "${now_mode}" ]]; then
		ssr_port=`${jq_file} '.server_port' ${config_user_file}`
		Del_iptables
		Add_iptables
	fi
	Restart_SSR
}
# 切換端口模式
Port_mode_switching(){
	SSR_installation_status
	if [[ -z "${now_mode}" ]]; then
		echo && echo -e "	目前模式: ${Green_font_prefix}單端口${Font_color_suffix}" && echo
		echo -e "確定要切換為 多端口模式？[y/N]"
		stty erase '^H' && read -p "(預設: n):" mode_yn
		[[ -z ${mode_yn} ]] && mode_yn="n"
		if [[ ${mode_yn} == [Yy] ]]; then
			port=`${jq_file} '.server_port' ${config_user_file}`
			Set_config_all
			Write_configuration_many
			Del_iptables
			Add_iptables
			Save_iptables
			Restart_SSR
		else
			echo && echo "	已取消..." && echo
		fi
	else
		echo && echo -e "	目前模式: ${Green_font_prefix}多端口${Font_color_suffix}" && echo
		echo -e "確定要切換為 單端口模式？[y/N]"
		stty erase '^H' && read -p "(預設: n):" mode_yn
		[[ -z ${mode_yn} ]] && mode_yn="n"
		if [[ ${mode_yn} == [Yy] ]]; then
			user_total=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | wc -l`
			for((integer = 1; integer <= ${user_total}; integer++))
			do
				port=`${jq_file} '.port_password' ${config_user_file} | sed '$d' | sed "1d" | awk -F ":" '{print $1}' | sed -n "${integer}p" | sed -r 's/.*\"(.+)\".*/\1/'`
				Del_iptables
			done
			Set_config_all
			Write_configuration
			Add_iptables
			Restart_SSR
		else
			echo && echo "	已取消..." && echo
		fi
	fi
}
Start_SSR(){
	SSR_installation_status
	check_pid
	[[ ! -z ${PID} ]] && echo -e "${Error} ShadowsocksR 正在運行 !" && exit 1
	/etc/init.d/ssr start
	check_pid
	[[ ! -z ${PID} ]] && View_User
}
Stop_SSR(){
	SSR_installation_status
	check_pid
	[[ -z ${PID} ]] && echo -e "${Error} ShadowsocksR 未運行 !" && exit 1
	/etc/init.d/ssr stop
}
Restart_SSR(){
	SSR_installation_status
	check_pid
	[[ ! -z ${PID} ]] && /etc/init.d/ssr stop
	/etc/init.d/ssr start
	check_pid
	[[ ! -z ${PID} ]] && View_User
}
View_Log(){
	SSR_installation_status
	[[ ! -e ${ssr_log_file} ]] && echo -e "${Error} ShadowsocksR日誌文件不存在 !" && exit 1
	echo && echo -e "${Tip} 按 ${Red_font_prefix}Ctrl+C${Font_color_suffix} 終止查看日誌" && echo
	tail -f ${ssr_log_file}
}
# 銳速
Configure_Server_Speeder(){
	echo && echo -e "你要做什麼？
 ${Green_font_prefix}1.${Font_color_suffix} 安裝 銳速
 ${Green_font_prefix}2.${Font_color_suffix} 卸載 銳速
————————
 ${Green_font_prefix}3.${Font_color_suffix} 啟動 銳速
 ${Green_font_prefix}4.${Font_color_suffix} 停止 銳速
 ${Green_font_prefix}5.${Font_color_suffix} 重啟 銳速
 ${Green_font_prefix}6.${Font_color_suffix} 查看 銳速 狀態
 
 注意： 銳速和LotServer不能同時安裝/啟動！" && echo
	stty erase '^H' && read -p "(預設: 取消):" server_speeder_num
	[[ -z "${server_speeder_num}" ]] && echo "已取消..." && exit 1
	if [[ ${server_speeder_num} == "1" ]]; then
		Install_ServerSpeeder
	elif [[ ${server_speeder_num} == "2" ]]; then
		Server_Speeder_installation_status
		Uninstall_ServerSpeeder
	elif [[ ${server_speeder_num} == "3" ]]; then
		Server_Speeder_installation_status
		${Server_Speeder_file} start
		${Server_Speeder_file} status
	elif [[ ${server_speeder_num} == "4" ]]; then
		Server_Speeder_installation_status
		${Server_Speeder_file} stop
	elif [[ ${server_speeder_num} == "5" ]]; then
		Server_Speeder_installation_status
		${Server_Speeder_file} restart
		${Server_Speeder_file} status
	elif [[ ${server_speeder_num} == "6" ]]; then
		Server_Speeder_installation_status
		${Server_Speeder_file} status
	else
		echo -e "${Error} 請輸入正確的數字(1-6)" && exit 1
	fi
}
Install_ServerSpeeder(){
	[[ -e ${Server_Speeder_file} ]] && echo -e "${Error} 銳速(Server Speeder) 已安裝 !" && exit 1
	cd /root
	#借用91yun.rog的開心版銳速
	wget -N --no-check-certificate https://raw.githubusercontent.com/91yun/serverspeeder/master/serverspeeder.sh
	[[ ! -e "serverspeeder.sh" ]] && echo -e "${Error} 銳速安裝腳本下載失敗 !" && exit 1
	bash serverspeeder.sh
	sleep 2s
	PID=`ps -ef |grep -v grep |grep "serverspeeder" |awk '{print $2}'`
	if [[ ! -z ${PID} ]]; then
		rm -rf /root/serverspeeder.sh
		rm -rf /root/91yunserverspeeder
		rm -rf /root/91yunserverspeeder.tar.gz
		echo -e "${Info} 銳速(Server Speeder) 安裝完成 !" && exit 1
	else
		echo -e "${Error} 銳速(Server Speeder) 安裝失敗 !" && exit 1
	fi
}
Uninstall_ServerSpeeder(){
	echo "確定要卸載 銳速(Server Speeder)？[y/N]" && echo
	stty erase '^H' && read -p "(預設: n):" unyn
	[[ -z ${unyn} ]] && echo && echo "已取消..." && exit 1
	if [[ ${unyn} == [Yy] ]]; then
		chattr -i /serverspeeder/etc/apx*
		/serverspeeder/bin/serverSpeeder.sh uninstall -f
		echo && echo "銳速(Server Speeder) 卸載完成 !" && echo
	fi
}
# LotServer
Configure_LotServer(){
	echo && echo -e "你要做什麼？
 ${Green_font_prefix}1.${Font_color_suffix} 安裝 LotServer
 ${Green_font_prefix}2.${Font_color_suffix} 卸載 LotServer
————————
 ${Green_font_prefix}3.${Font_color_suffix} 啟動 LotServer
 ${Green_font_prefix}4.${Font_color_suffix} 停止 LotServer
 ${Green_font_prefix}5.${Font_color_suffix} 重啟 LotServer
 ${Green_font_prefix}6.${Font_color_suffix} 查看 LotServer 狀態
 
 注意： 銳速和LotServer不能同時安裝/啟動！" && echo
	stty erase '^H' && read -p "(預設: 取消):" lotserver_num
	[[ -z "${lotserver_num}" ]] && echo "已取消..." && exit 1
	if [[ ${lotserver_num} == "1" ]]; then
		Install_LotServer
	elif [[ ${lotserver_num} == "2" ]]; then
		LotServer_installation_status
		Uninstall_LotServer
	elif [[ ${lotserver_num} == "3" ]]; then
		LotServer_installation_status
		${LotServer_file} start
		${LotServer_file} status
	elif [[ ${lotserver_num} == "4" ]]; then
		LotServer_installation_status
		${LotServer_file} stop
	elif [[ ${lotserver_num} == "5" ]]; then
		LotServer_installation_status
		${LotServer_file} restart
		${LotServer_file} status
	elif [[ ${lotserver_num} == "6" ]]; then
		LotServer_installation_status
		${LotServer_file} status
	else
		echo -e "${Error} 請輸入正確的數字(1-6)" && exit 1
	fi
}
Install_LotServer(){
	[[ -e ${LotServer_file} ]] && echo -e "${Error} LotServer 已安裝 !" && exit 1
	#Github: https://github.com/0oVicero0/serverSpeeder_Install
	wget --no-check-certificate -qO /tmp/appex.sh "https://raw.githubusercontent.com/0oVicero0/serverSpeeder_Install/master/appex.sh"
	[[ ! -e "/tmp/appex.sh" ]] && echo -e "${Error} LotServer 安裝腳本下載失敗 !" && exit 1
	bash /tmp/appex.sh 'install'
	sleep 2s
	PID=`ps -ef |grep -v grep |grep "appex" |awk '{print $2}'`
	if [[ ! -z ${PID} ]]; then
		echo -e "${Info} LotServer 安裝完成 !" && exit 1
	else
		echo -e "${Error} LotServer 安裝失敗 !" && exit 1
	fi
}
Uninstall_LotServer(){
	echo "確定要卸載 LotServer？[y/N]" && echo
	stty erase '^H' && read -p "(預設: n):" unyn
	[[ -z ${unyn} ]] && echo && echo "已取消..." && exit 1
	if [[ ${unyn} == [Yy] ]]; then
		wget --no-check-certificate -qO /tmp/appex.sh "https://raw.githubusercontent.com/0oVicero0/serverSpeeder_Install/master/appex.sh" && bash /tmp/appex.sh 'uninstall'
		echo && echo "LotServer 卸載完成 !" && echo
	fi
}
# BBR
Configure_BBR(){
	echo && echo -e "  你要做什麼？
	
 ${Green_font_prefix}1.${Font_color_suffix} 安裝 BBR
————————
 ${Green_font_prefix}2.${Font_color_suffix} 啟動 BBR
 ${Green_font_prefix}3.${Font_color_suffix} 停止 BBR
 ${Green_font_prefix}4.${Font_color_suffix} 查看 BBR 狀態" && echo
echo -e "${Green_font_prefix} [安裝前 請注意] ${Font_color_suffix}
1. 安裝開啟BBR，需要更換內核，存在更換失敗等風險(重啟後無法開機)
2. 本腳本僅支持 Debian / Ubuntu 系統更換內核，OpenVZ和Docker 不支持更換內核
3. Debian 更換內核過程中會提示 [ 是否終止卸載內核 ] ，請選擇 ${Green_font_prefix} NO ${Font_color_suffix}
4. 安裝BBR並重啟服務器後，需要重新運行腳本 啟動BBR" && echo
	stty erase '^H' && read -p "(預設: 取消):" bbr_num
	[[ -z "${bbr_num}" ]] && echo "已取消..." && exit 1
	if [[ ${bbr_num} == "1" ]]; then
		Install_BBR
	elif [[ ${bbr_num} == "2" ]]; then
		Start_BBR
	elif [[ ${bbr_num} == "3" ]]; then
		Stop_BBR
	elif [[ ${bbr_num} == "4" ]]; then
		Status_BBR
	else
		echo -e "${Error} 請輸入正確的數字(1-4)" && exit 1
	fi
}
Install_BBR(){
	[[ ${release} = "centos" ]] && echo -e "${Error} 本腳本不支持 CentOS系統安裝 BBR !" && exit 1
	BBR_installation_status
	bash bbr.sh
}
Start_BBR(){
	BBR_installation_status
	bash bbr.sh start
}
Stop_BBR(){
	BBR_installation_status
	bash bbr.sh stop
}
Status_BBR(){
	BBR_installation_status
	bash bbr.sh status
}
# 其他功能
Other_functions(){
	echo && echo -e "  你要做什麼？
	
  ${Green_font_prefix}1.${Font_color_suffix} 配置 BBR
  ${Green_font_prefix}2.${Font_color_suffix} 配置 銳速(ServerSpeeder)
  ${Green_font_prefix}3.${Font_color_suffix} 配置 LotServer(銳速母公司)
  注意： 銳速/LotServer/BBR 不支持 OpenVZ！
  注意： 銳速和LotServer不能同時安裝/啟動！
————————————
  ${Green_font_prefix}4.${Font_color_suffix} 一鍵封禁 BT/PT/SPAM (iptables)
  ${Green_font_prefix}5.${Font_color_suffix} 一鍵解封 BT/PT/SPAM (iptables)
  ${Green_font_prefix}6.${Font_color_suffix} 切換 ShadowsocksR日誌輸出模式
  ——說明：SSR預設只輸出錯誤日誌，此項可切換為輸出詳細的訪問日誌" && echo
	stty erase '^H' && read -p "(預設: 取消):" other_num
	[[ -z "${other_num}" ]] && echo "已取消..." && exit 1
	if [[ ${other_num} == "1" ]]; then
		Configure_BBR
	elif [[ ${other_num} == "2" ]]; then
		Configure_Server_Speeder
	elif [[ ${other_num} == "3" ]]; then
		Configure_LotServer
	elif [[ ${other_num} == "4" ]]; then
		BanBTPTSPAM
	elif [[ ${other_num} == "5" ]]; then
		UnBanBTPTSPAM
	elif [[ ${other_num} == "6" ]]; then
		Set_config_connect_verbose_info
	else
		echo -e "${Error} 請輸入正確的數字 [1-6]" && exit 1
	fi
}
# 封禁 BT PT SPAM
BanBTPTSPAM(){
	wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ban_iptables.sh && chmod +x ban_iptables.sh && bash ban_iptables.sh banall
	rm -rf banall.sh
}
# 解封 BT PT SPAM
UnBanBTPTSPAM(){
	wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ban_iptables.sh && chmod +x ban_iptables.sh && bash ban_iptables.sh unbanall
	rm -rf banall.sh
}
Set_config_connect_verbose_info(){
	SSR_installation_status
	Get_User
	if [[ ${connect_verbose_info} = "0" ]]; then
		echo && echo -e "目前日誌模式: ${Green_font_prefix}簡單模式（只輸出錯誤日誌）${Font_color_suffix}" && echo
		echo -e "確定要切換為 ${Green_font_prefix}詳細模式（輸出詳細連接日誌+錯誤日誌）${Font_color_suffix}？[y/N]"
		stty erase '^H' && read -p "(預設: n):" connect_verbose_info_ny
		[[ -z "${connect_verbose_info_ny}" ]] && connect_verbose_info_ny="n"
		if [[ ${connect_verbose_info_ny} == [Yy] ]]; then
			ssr_connect_verbose_info="1"
			Modify_config_connect_verbose_info
			Restart_SSR
		else
			echo && echo "	已取消..." && echo
		fi
	else
		echo && echo -e "目前日誌模式: ${Green_font_prefix}詳細模式（輸出詳細連接日誌+錯誤日誌）${Font_color_suffix}" && echo
		echo -e "確定要切換為 ${Green_font_prefix}簡單模式（只輸出錯誤日誌）${Font_color_suffix}？[y/N]"
		stty erase '^H' && read -p "(預設: n):" connect_verbose_info_ny
		[[ -z "${connect_verbose_info_ny}" ]] && connect_verbose_info_ny="n"
		if [[ ${connect_verbose_info_ny} == [Yy] ]]; then
			ssr_connect_verbose_info="0"
			Modify_config_connect_verbose_info
			Restart_SSR
		else
			echo && echo "	已取消..." && echo
		fi
	fi
}
Update_Shell(){
	echo -e "目前版本為 [ ${sh_ver} ]，開始檢測最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "https://softs.fun/Bash/ssr.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1) && sh_new_type="softs"
	[[ -z ${sh_new_ver} ]] && sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ssr.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1) && sh_new_type="github"
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 檢測最新版本失敗 !" && exit 0
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "發現新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
		stty erase '^H' && read -p "(預設: y):" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			if [[ $sh_new_type == "softs" ]]; then
				wget -N --no-check-certificate https://softs.fun/Bash/ssr.sh && chmod +x ssr.sh
			else
				wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ssr.sh && chmod +x ssr.sh
			fi
			echo -e "腳本已更新為最新版本[ ${sh_new_ver} ] !"
		else
			echo && echo "	已取消..." && echo
		fi
	else
		echo -e "目前已是最新版本[ ${sh_new_ver} ] !"
	fi
}
# 顯示 菜單狀態
menu_status(){
	if [[ -e ${config_user_file} ]]; then
		check_pid
		if [[ ! -z "${PID}" ]]; then
			echo -e " 目前狀態: ${Green_font_prefix}已安裝${Font_color_suffix} 並 ${Green_font_prefix}已啟動${Font_color_suffix}"
		else
			echo -e " 目前狀態: ${Green_font_prefix}已安裝${Font_color_suffix} 但 ${Red_font_prefix}未啟動${Font_color_suffix}"
		fi
		now_mode=$(cat "${config_user_file}"|grep '"port_password"')
		if [[ -z "${now_mode}" ]]; then
			echo -e " 目前模式: ${Green_font_prefix}單端口${Font_color_suffix}"
		else
			echo -e " 目前模式: ${Green_font_prefix}多端口${Font_color_suffix}"
		fi
	else
		echo -e " 目前狀態: ${Red_font_prefix}未安裝${Font_color_suffix}"
	fi
}
check_sys
[[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "centos" ]] && echo -e "${Error} 本腳本不支持目前系統 ${release} !" && exit 1
echo -e "  ShadowsocksR 一鍵管理腳本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
  ---- Toyo | doub.io/ss-jc42 ----

  ${Green_font_prefix}1.${Font_color_suffix} 安裝 ShadowsocksR
  ${Green_font_prefix}2.${Font_color_suffix} 更新 ShadowsocksR
  ${Green_font_prefix}3.${Font_color_suffix} 卸載 ShadowsocksR
  ${Green_font_prefix}4.${Font_color_suffix} 安裝 libsodium(chacha20)
————————————
  ${Green_font_prefix}5.${Font_color_suffix} 查看 帳號資訊
  ${Green_font_prefix}6.${Font_color_suffix} 顯示 連接資訊
  ${Green_font_prefix}7.${Font_color_suffix} 設定 用戶配置
  ${Green_font_prefix}8.${Font_color_suffix} 手動 修改配置
  ${Green_font_prefix}9.${Font_color_suffix} 切換 端口模式
————————————
 ${Green_font_prefix}10.${Font_color_suffix} 啟動 ShadowsocksR
 ${Green_font_prefix}11.${Font_color_suffix} 停止 ShadowsocksR
 ${Green_font_prefix}12.${Font_color_suffix} 重啟 ShadowsocksR
 ${Green_font_prefix}13.${Font_color_suffix} 查看 ShadowsocksR 日誌
————————————
 ${Green_font_prefix}14.${Font_color_suffix} 其他功能
 ${Green_font_prefix}15.${Font_color_suffix} 升級腳本
 "
menu_status
echo && stty erase '^H' && read -p "請輸入數字 [1-15]：" num
case "$num" in
	1)
	Install_SSR
	;;
	2)
	Update_SSR
	;;
	3)
	Uninstall_SSR
	;;
	4)
	Install_Libsodium
	;;
	5)
	View_User
	;;
	6)
	View_user_connection_info
	;;
	7)
	Modify_Config
	;;
	8)
	Manually_Modify_Config
	;;
	9)
	Port_mode_switching
	;;
	10)
	Start_SSR
	;;
	11)
	Stop_SSR
	;;
	12)
	Restart_SSR
	;;
	13)
	View_Log
	;;
	14)
	Other_functions
	;;
	15)
	Update_Shell
	;;
	*)
	echo -e "${Error} 請輸入正確的數字 [1-15]"
	;;
esac
