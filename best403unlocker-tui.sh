#!/usr/bin/env bash
CONFIG_FILE="/etc/best403unlocker.conf"
LOG_FILE="/var/log/best403unlocker-tui.log"

# Function to display the main menu
main_menu() {
    password=
    choice=$(whiptail --title "Best403Unlcoker TUI" --menu "Choose an option:" 15 60 5 \
    "Run DNS analyzer" "find the most speedful dns" \
    "Auto configure DNS" "Set best DNS on selected interfaces" \
    "Save file" "Download file with the best dns" \
    "Advance setting" "change configuration" \
    "Exit" "Exit the program" \
    3>&1 1>&2 2>&3)

    case "$choice" in
        "Run DNS analyzer")
            best_dns_finder
            ;;
        "Auto configure DNS")
            auto_configure_dns
            ;;
        "Save file")
            download_file_with_best_dns
            ;;
        "Advance setting")
            change_settings
            ;;
        "Exit")
            exit
            ;;
        *)
            ;;
    esac
}

# Run analyzer and set global DNS variable
run_analyzer() {
    local test_file_url choices selected_options status
    test_file_url=$(whiptail --title "add test file url" --inputbox "please type your url that you want to be checked" 15 60 "${file_url:-}" 3>&1 1>&2 2>&3) || return 1

    if grep -q "^file_url=" "$CONFIG_FILE" ; then
        sed -i "s|^file_url=.*|file_url=$test_file_url|" "$CONFIG_FILE"
    fi

    choices=$(whiptail --title "choose engine otherwise it runs on system" --checklist "Choose options:" 15 60 1 \
            "docker" "(suggested)" ON \
    3>&1 1>&2 2>&3) || return 1
    read -r -a selected_options <<< "$(echo "$choices" | tr -d '"')"

    if [[ " ${selected_options[*]} " =~ " docker " ]]; then
        docker run --env-file "$CONFIG_FILE" armantaherighaletaki/best403unlocker 2>&1 | tee "$LOG_FILE"
        status=$?
        if [ $status -eq 0 ] && grep -q permission "$LOG_FILE"; then
            password_checker
            echo "$password" | sudo -S docker run --env-file "$CONFIG_FILE" armantaherighaletaki/best403unlocker | tee "$LOG_FILE" 2>&1
        elif [ $status -ne 0 ]; then
            whiptail --title "Error" --yesno "An error occurred. See $LOG_FILE for more info.\nDo you want to try again?" 15 60
            status=$?
            if [ $status -eq 0 ]; then
                run_analyzer
                return $?
            else
                return 1
            fi
        fi
    else
        password_checker
        best403unlocker | tee "$LOG_FILE"
    fi

    DNS=$(grep best "$LOG_FILE" | cut -d' ' -f5)
    return 0
}

best_dns_finder() {
    if ! run_analyzer; then
        main
        return
    fi

    whiptail --title "DNS analyzer" --msgbox "Best DNS:\n$DNS" 15 60

    if whiptail --title "Confirmation" --yesno "set DNS to system" 10 60 ; then
        password_checker
        echo "$password" | sudo -S bash -c "echo 'nameserver $DNS' > /etc/resolv.conf"
    fi
}

auto_configure_dns() {
    local interfaces options choices selected

    run_analyzer || return

    interfaces=$(get_available_interfaces)
    if [ -z "$interfaces" ]; then
        whiptail --title "Error" --msgbox "No network interfaces found." 15 60
        return
    fi

    options=()
    for iface in $interfaces; do
        options+=("$iface" "" OFF)
    done

    choices=$(whiptail --title "Select Interfaces" --checklist "Choose interfaces to apply DNS:" 15 60 ${#options[@]} "${options[@]}" 3>&1 1>&2 2>&3) || return
    read -r -a selected <<< "$(echo "$choices" | tr -d '"')"
    if [ ${#selected[@]} -eq 0 ]; then
        whiptail --title "No Selection" --msgbox "No interfaces selected." 15 60
        return
    fi

    apply_dns_to_interfaces "$DNS" "${selected[@]}"
    whiptail --title "DNS Configured" --msgbox "Best DNS $DNS applied." 15 60
}

download_file_with_best_dns() {
    local download_url save_filepath

    download_url=$(whiptail --title "add file url" --inputbox "please type the url that you wnat to be downloaded" 15 60 "$download_url" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ]; then
        main
    fi

    save_filepath=$(echo "$download_url" | grep -o '[^/]*$')
    save_filepath=$HOME/Downloads/$save_filepath
    save_filepath=$(whiptail --title "save file as " --inputbox "choose the location to save the file" 15 60 "$save_filepath" 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ]; then
        main
    fi

    run_analyzer || return

    password_checker
    echo "$password" | sudo -S bash -c "cp /etc/resolv.conf /etc/resolv.conf.bakup"
    echo "$password" | sudo -S bash -c "echo 'nameserver $DNS' > /etc/resolv.conf"

    wget --no-dns-cache "$download_url" -O "$save_filepath" 2>&1 | tee "$LOG_FILE"
    if grep -q "No such file or directory" "$LOG_FILE" ; then
        whiptail --title "Error" --msgbox "An error occurred. See $LOG_FILE for more info." 15 60
    else
        whiptail --title "Download Complete" --msgbox "The download has been completed successfully!" 15 60
    fi
    echo "$password" | sudo -S bash -c "mv /etc/resolv.conf.bakup /etc/resolv.conf"
}

change_settings() {
 echo 'hello'
}

# Checks the password if a sudo command is executed
password_checker(){
    password=
    if ! echo "$password" | sudo -S ls > /dev/null 2>&1 && [[ -z $password ]]
    then
        while true; do
            if ! password=$(whiptail --title "Permission Denied" --passwordbox "Input your sudo password" 15 60 3>&1 1>&2 2>&3)
            then
                if ! echo "$password" | sudo -S ls > /dev/null 2>&1
                then
                    break
                fi
            else
                main
            fi
        done
    fi
}

get_available_interfaces() {
    if ! command -v ip >/dev/null 2>&1; then
        return
    fi
    ip -o link show | awk -F': ' '{print $2}' | cut -d@ -f1 | grep -v '^lo$'
}

apply_dns_to_interfaces() {
    local dns="$1"; shift
    local interfaces=("$@")

    if command -v nmcli >/dev/null 2>&1; then
        local conn
        for iface in "${interfaces[@]}"; do
            mapfile -t conn < <(nmcli -t -f UUID,DEVICE connection show --active | awk -F: -v iface="$iface" '$2==iface {print $1}')
            for c in "${conn[@]}"; do
                nmcli connection modify "$c" ipv4.dns "$dns" ipv4.ignore-auto-dns yes >/dev/null 2>&1
                nmcli connection up "$c" >/dev/null 2>&1
            done
        done
    elif command -v resolvectl >/dev/null 2>&1; then
        for iface in "${interfaces[@]}"; do
            resolvectl dns "$iface" "$dns" >/dev/null 2>&1
        done
    else
        password_checker
        echo "$password" | sudo -S cp /etc/resolv.conf /etc/resolv.conf.bakup >/dev/null 2>&1
        echo "$password" | sudo -S bash -c "echo 'nameserver $dns' > /etc/resolv.conf"
    fi
}

check_and_source_env() {
    if [ ! -f "$CONFIG_FILE" ]; then
    wget -cq https://raw.githubusercontent.com/ArmanTaheriGhaleTaki/best403unlocker/main/.env -O "$CONFIG_FILE"
 fi
# shellcheck source=/etc/best403unlocker.conf
    source "$CONFIG_FILE"
}
check_run_with_root_accsses(){
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (sudo)"
  exit 1
fi
}
# Main function
main() {

    check_run_with_root_accsses
    check_and_source_env
    while true; do
        main_menu
    done
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
