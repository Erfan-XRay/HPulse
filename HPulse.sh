#!/bin/bash

# Define colors for better terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RESET='\033[0m' # No Color
BOLD_GREEN='\033[1;32m' # Bold Green for menu title

# --- Global Paths and Markers ---
# Use readlink -f to get the canonical path of the script, resolving symlinks and /dev/fd/ issues
TRUST_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$TRUST_SCRIPT_PATH")"
SETUP_MARKER_FILE="/var/lib/frpulse/.setup_complete" # Changed TrustTunnel to FRPulse

# --- Script Version ---
SCRIPT_VERSION="1.8.0" # Define the script version - UPDATED TO 1.8.0

# --- Helper Functions ---

# Function to draw a colored line for menu separation
draw_line() {
  local color="$1"
  local char="$2"
  local length=${3:-40} # Default length 40 if not provided
  printf "${color}"
  for ((i=0; i<length; i++)); do
    printf "$char"
  done
  printf "${RESET}\n"
}

# Function to print success messages in green
print_success() {
  local message="$1"
  echo -e "\033[0;32m✅ $message\033[0m" # Green color for success messages
}

# Function to print error messages in red
print_error() {
  local message="$1"
  echo -e "\033[0;31m❌ $message\033[0m" # Red color for error messages
}

# Function to show service logs and return to a "menu"
show_service_logs() {
  local service_name="$1"
  clear # Clear the screen before showing logs
  echo -e "\033[0;34m--- Displaying logs for $service_name ---\033[0m" # Blue color for header

  # Display the last 50 lines of logs for the specified service
  # --no-pager ensures the output is direct to the terminal without opening 'less'
  sudo journalctl -u "$service_name" -n 50 --no-pager

  echo ""
  echo -e "\033[1;33mPress any key to return to the previous menu...\033[0m" # Yellow color for prompt
  read -n 1 -s -r # Read a single character, silent, raw input

  clear
}

# Function to draw a green line (used for main menu border)
draw_green_line() {
  echo -e "${GREEN}+--------------------------------------------------------+${RESET}"
}

# --- Validation Functions ---

# Function to validate an email address
validate_email() {
  local email="$1"
  if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
    return 0 # Valid
  else
    return 1 # Invalid
  fi
}

# Function to validate a port number
validate_port() {
  local port="$1"
  if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
    return 0 # Valid
  else
    return 1 # Invalid
  fi
}

# Function to validate a domain or IP address
validate_host() {
  local host="$1"
  # Regex for IPv4 address
  local ipv4_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
  # Regex for IPv6 address (simplified, covers common formats including compressed ones)
  # This regex is a balance between strictness and covering common valid IPv6 formats.
  # It does not cover all extremely complex valid IPv6 cases (e.g., IPv4-mapped IPv6),
  # but should be sufficient for typical user input.
  local ipv6_regex="^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){1,7}:(\b[0-9a-fA-F]{1,4}\b){1,7}$|^([0-9a-fA-F]{1,4}:){1,6}(:[0-9a-fA-F]{1,4}){1,2}$|^([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,3}$|^([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,4}$|^([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,5}$|^([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,6}$|^[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,7}|:)$|^::((:[0-9a-fA-F]{1,4}){1,7}|[0-9a-fA-F]{1,4})$|^[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$|^::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$"
  # Regex for domain name
  local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$"

  if [[ "$host" =~ $ipv4_regex ]] || [[ "$host" =~ $ipv6_regex ]] || [[ "$host" =~ $domain_regex ]]; then
    return 0 # Valid
  else
    return 1 # Invalid
  fi
}

# Function to validate IP:Port format
validate_ip_port() {
  local input="$1"
  local host_part=""
  local port_part=""

  # Check for IPv6 with brackets
  if [[ "$input" =~ ^\[(.*)\]:([0-9]+)$ ]]; then
    host_part="${BASH_REMATCH[1]}"
    port_part="${BASH_REMATCH[2]}"
  elif [[ "$input" =~ ^([^:]+):([0-9]+)$ ]]; then
    host_part="${BASH_REMATCH[1]}"
    port_part="${BASH_REMATCH[2]}"
  else
    return 1 # Does not match IP:Port pattern
  fi

  if validate_host "$host_part" && validate_port "$port_part"; then
    return 0 # Valid
  else
    return 1 # Invalid host or port
  fi
}


# Update cron job logic to include Hysteria
reset_timer() {
  local service_to_restart="$1" # Optional: service name passed as argument

  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ⏰ Schedule Service Restart${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  if [[ -z "$service_to_restart" ]]; then
    echo -e "👉 ${WHITE}Which service do you want to restart (e.g., 'nginx', 'hysteria-server-myname', 'frpulse')? ${RESET}"
    read -p "" service_to_restart
    echo ""
  fi

  if [[ -z "$service_to_restart" ]]; then
    print_error "Service name cannot be empty. Aborting scheduling."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  if [ ! -f "/etc/systemd/system/${service_to_restart}.service" ]; then
    print_error "Service '$service_to_restart' does not exist on this system. Cannot schedule restart."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${CYAN}Scheduling restart for service: ${WHITE}$service_to_restart${RESET}"
  echo ""
  echo "Please select a time interval for the service to restart RECURRINGLY:"
  echo -e "  ${YELLOW}1)${RESET} ${WHITE}Every 30 minutes${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${WHITE}Every 1 hour${RESET}"
  echo -e "  ${YELLOW}3)${RESET} ${WHITE}Every 2 hours${RESET}"
  echo -e "  ${YELLOW}4)${RESET} ${WHITE}Every 4 hours${RESET}"
  echo -e "  ${YELLOW}5)${RESET} ${WHITE}Every 6 hours${RESET}"
  echo -e "  ${YELLOW}6)${RESET} ${WHITE}Every 12 hours${RESET}"
  echo -e "  ${YELLOW}7)${RESET} ${WHITE}Every 24 hours${RESET}"
  echo ""
  read -p "👉 Enter your choice (1-7): " choice
  echo ""

  local cron_minute=""
  local cron_hour=""
  local cron_day_of_month="*"
  local cron_month="*"
  local cron_day_of_week="*"
  local description=""
  local cron_tag=""

  if [[ "$service_to_restart" == hysteria-* ]]; then
      cron_tag="Hysteria"
  else
      cron_tag="FRPulse" # Keep this for existing FRPulse cron jobs cleanup
  fi


  case "$choice" in
    1)
      cron_minute="*/30"
      cron_hour="*"
      description="every 30 minutes"
      ;;
    2)
      cron_minute="0"
      cron_hour="*/1"
      description="every 1 hour"
      ;;
    3)
      cron_minute="0"
      cron_hour="*/2"
      description="every 2 hours"
      ;;
    4)
      cron_minute="0"
      cron_hour="*/4"
      description="every 4 hours"
      ;;
    5)
      cron_minute="0"
      cron_hour="*/6"
      description="every 6 hours"
      ;;
    6)
      cron_minute="0"
      cron_hour="*/12"
      description="every 12 hours"
      ;;
    7)
      cron_minute="0"
      cron_hour="0"
      description="every 24 hours (daily at midnight)"
      ;;
    *)
      echo -e "${RED}❌ Invalid choice. No cron job will be scheduled.${RESET}"
      echo ""
      echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
      read -p ""
      return 1
      ;;
  esac

  echo -e "${CYAN}Scheduling '$service_to_restart' to restart $description...${RESET}"
  echo ""
  
  local cron_command="/usr/bin/systemctl restart $service_to_restart >> /var/log/${cron_tag}_cron.log 2>&1"
  local cron_job_entry="$cron_minute $cron_hour $cron_day_of_month $cron_month $cron_day_of_week $cron_command # ${cron_tag} automated restart for $service_to_restart"

  local temp_cron_file=$(mktemp)
  if ! sudo crontab -l &> /dev/null; then
      echo "" | sudo crontab -
  fi
  sudo crontab -l > "$temp_cron_file"

  # Remove existing cron jobs for both FRPulse and Hysteria for this service
  sed -i "/# FRPulse automated restart for $service_to_restart$/d" "$temp_cron_file"
  sed -i "/# Hysteria automated restart for $service_to_restart$/d" "$temp_cron_file"

  echo "$cron_job_entry" >> "$temp_cron_file"

  if sudo crontab "$temp_cron_file"; then
    print_success "Successfully scheduled a restart for '$service_to_restart' $description."
    echo -e "${CYAN}   The cron job entry looks like this:${RESET}"
    echo -e "${WHITE}   $cron_job_entry${RESET}"
    echo -e "${CYAN}   Logs will be written to: ${WHITE}/var/log/${cron_tag}_cron.log${RESET}"
  else
    print_error "Failed to schedule the cron job. Check permissions or cron service status.${RESET}"
  fi

  rm -f "$temp_cron_file"

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

delete_cron_job_action() {
  clear
  echo ""
  draw_line "$RED" "=" 40
  echo -e "${RED}     🗑️ Delete Scheduled Restart (Cron)${RESET}"
  draw_line "$RED" "=" 40
  echo ""

  echo -e "${CYAN}🔍 Searching for Hysteria related services with scheduled restarts...${RESET}" # Updated message

  # Only search for Hysteria cron jobs, but keep the FRPulse grep for existing ones
  mapfile -t services_with_cron < <(sudo crontab -l 2>/dev/null | grep -E "# (FRPulse|Hysteria) automated restart for" | awk '{print $NF}' | sort -u)

  local service_names=()
  for service_comment in "${services_with_cron[@]}"; do
    local extracted_name=$(echo "$service_comment" | sed -E 's/# (FRPulse|Hysteria) automated restart for //')
    service_names+=("$extracted_name")
  done

  if [ ${#service_names[@]} -eq 0 ]; then
    print_error "No Hysteria or legacy FRPulse services with scheduled cron jobs found." # Updated message
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${CYAN}📋 Please select a service to delete its scheduled restart:${RESET}"
  service_names+=("Back to previous menu")
  select selected_service_name in "${service_names[@]}"; do
    if [[ "$selected_service_name" == "Back to previous menu" ]]; then
      echo -e "${YELLOW}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_service_name" ]; then
      break
    else
      print_error "Invalid selection. Please enter a valid number."
    fi
  done
  echo ""

  if [[ -z "$selected_service_name" ]]; then
    print_error "No service selected. Aborting."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${CYAN}Attempting to delete cron job for '$selected_service_name'...${RESET}"

  local temp_cron_file=$(mktemp)
  if ! sudo crontab -l &> /dev/null; then
      print_error "Crontab is empty or not accessible. Nothing to delete."
      rm -f "$temp_cron_file"
      echo ""
      echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
      read -p ""
      return 1
  fi
  sudo crontab -l > "$temp_cron_file"

  # Remove existing cron jobs for both FRPulse and Hysteria for this service
  sed -i "/# FRPulse automated restart for $selected_service_name$/d" "$temp_cron_file"
  sed -i "/# Hysteria automated restart for $selected_service_name$/d" "$temp_cron_file"

  echo "$cron_job_entry" >> "$temp_cron_file"

  if sudo crontab "$temp_cron_file"; then
    print_success "Successfully removed scheduled restart for '$selected_service_name'."
    echo -e "${WHITE}You can verify with: ${YELLOW}sudo crontab -l${RESET}"
  else
    print_error "Failed to delete cron job. It might not exist or there's a permission issue.${RESET}"
  fi

  rm -f "$temp_cron_file"

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Renamed to reflect only Hysteria and Direct management
uninstall_hysteria_and_direct_action() {
  clear
  echo ""
  echo -e "${RED}⚠️ Are you sure you want to uninstall Hysteria and remove all associated files and services? (y/N): ${RESET}" # Updated message
  read -p "" confirm
  echo ""

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🧹 Uninstalling Hysteria and cleaning up..." # Updated message

    # 1. Uninstall Hysteria using its official script
    echo -e "${CYAN}Running Hysteria uninstallation script...${RESET}"
    if bash <(curl -fsSL https://get.hy2.sh/) --remove; then
      print_success "Hysteria uninstallation script completed."
    else
      print_error "❌ Hysteria uninstallation script failed. Proceeding with manual cleanup."
    fi

    # --- Explicitly handle frpulse.service (server) - keep for cleanup of old installs ---
    local frpulse_server_service_name="frpulse.service"
    if systemctl list-unit-files --full --no-pager | grep -q "^$frpulse_server_service_name"; then
      echo "🛑 Stopping and disabling legacy FRPulse server service ($frpulse_server_service_name)..."
      sudo systemctl stop "$frpulse_server_service_name" > /dev/null 2>&1
      sudo systemctl disable "$frpulse_server_service_name" > /dev/null 2>&1
      sudo rm -f "/etc/systemd/system/$frpulse_server_service_name" > /dev/null 2>&1
      print_success "Legacy FRPulse server service removed."
    else
      echo "⚠️ Legacy FRPulse server service ($frpulse_server_service_name) not found. Skipping."
    fi

    # Find and remove all frpulse-* services (clients) - keep for cleanup of old installs
    echo "Searching for legacy FRPulse client services to remove..."
    mapfile -t frpulse_client_services < <(sudo systemctl list-unit-files --full --no-pager | grep '^frpulse-.*\.service' | awk '{print $1}')

    if [ ${#frpulse_client_services[@]} -gt 0 ]; then
      echo "🛑 Stopping and disabling legacy FRPulse client services..."
      for service_file in "${frpulse_client_services[@]}"; do
        local service_name=$(basename "$service_file")
        echo "  - Processing $service_name..."
        sudo systemctl stop "$service_name" > /dev/null 2>&1
        sudo systemctl disable "$service_name" > /dev/null 2>&1
        sudo rm -f "/etc/systemd/system/$service_name" > /dev/null 2>&1
      done
      print_success "All legacy FRPulse client services have been stopped, disabled, and removed."
    else
      echo "⚠️ No legacy FRPulse client services found to remove."
    fi

    # --- Handle Hysteria services ---
    echo "Searching for Hysteria services to remove..."
    mapfile -t hysteria_services < <(sudo systemctl list-unit-files --full --no-pager | grep '^hysteria-.*\.service' | awk '{print $1}')

    if [ ${#hysteria_services[@]} -gt 0 ]; then
      echo "🛑 Stopping and disabling Hysteria services..."
      for service_file in "${hysteria_services[@]}"; do
        local service_name=$(basename "$service_file")
        echo "  - Processing $service_name..."
        sudo systemctl stop "$service_name" > /dev/null 2>&1
        sudo systemctl disable "$service_name" > /dev/null 2>&1
        sudo rm -f "/etc/systemd/system/$service_name" > /dev/null 2>&1
      done
      print_success "All Hysteria services have been stopped, disabled, and removed."
    else
      echo "⚠️ No Hysteria services found to remove."
    fi

    # --- Handle Direct services ---
    echo "Searching for Direct tunnel services to remove..."
    mapfile -t direct_services < <(sudo systemctl list-unit-files --full --no-pager | grep 'frpulse-direct-client-' | awk '{print $1}') # Direct client services
    mapfile -t direct_server_service < <(sudo systemctl list-unit-files --full --no-pager | grep 'frpulse-direct.service' | awk '{print $1}') # Direct server service
    
    direct_services+=("${direct_server_service[@]}") # Add direct server to the list

    if [ ${#direct_services[@]} -gt 0 ]; then
      echo "🛑 Stopping and disabling Direct tunnel services..."
      for service_file in "${direct_services[@]}"; do
        local service_name=$(basename "$service_file")
        echo "  - Processing $service_name..."
        sudo systemctl stop "$service_name" > /dev/null 2>&1
        sudo systemctl disable "$service_name" > /dev/null 2>&1
        sudo rm -f "/etc/systemd/system/$service_name" > /dev/null 2>&1
      done
      print_success "All Direct tunnel services have been stopped, disabled, and removed."
    else
      echo "⚠️ No Direct tunnel services found to remove."
    fi


    sudo systemctl daemon-reload # Reload daemon after removing services

    # Remove frpulse config folder (keep for cleanup of old installs)
    if [ -d "$(pwd)/frpulse" ]; then
      echo "🗑️ Removing 'frpulse' config folder (legacy)..."
      rm -rf "$(pwd)/frpulse"
      print_success "'frpulse' config folder removed successfully."
    else
      echo "⚠️ 'frpulse' config folder not found."
    fi

    # 2. Remove /root/hysteria folder
    if [ -d "/root/hysteria" ]; then
      echo "🗑️ Removing /root/hysteria config folder..."
      sudo rm -rf "/root/hysteria"
      print_success "/root/hysteria config folder removed successfully."
    else
      echo "⚠️ /root/hysteria config folder not found. Skipping."
    fi

    # Remove rstun folder if exists (for direct tunnel)
    if [ -d "rstun" ]; then
      echo "🗑️ Removing 'rstun' folder..."
      rm -rf rstun
      print_success "'rstun' folder removed successfully."
    else
      echo "⚠️ 'rstun' folder not found."
    fi

    # Remove FRPulse and Hysteria related cron jobs
    echo -e "${CYAN}🧹 Removing any associated FRPulse and Hysteria cron jobs...${RESET}"
    (sudo crontab -l 2>/dev/null | grep -v "# FRPulse automated restart for" | grep -v "# Hysteria automated restart for") | sudo crontab -
    print_success "Associated cron jobs removed."

    # Remove setup marker file
    if [ -f "$SETUP_MARKER_FILE" ]; then
      echo "🗑️ Removing setup marker file..."
      sudo rm -f "$SETUP_MARKER_FILE"
      print_success "Setup marker file removed."
    fi

    print_success "Hysteria uninstallation and cleanup complete." # Updated message
  else
    echo -e "${YELLOW}❌ Uninstall cancelled.${RESET}"
  fi
  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}

# Update install_frpulse_action to install Hysteria and rename it
install_hysteria_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     📥 Installing Hysteria 2${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  echo -e "${CYAN}Downloading and installing Hysteria 2...${RESET}"
  if bash <(curl -fsSL https://get.hy2.sh); then
    print_success "Hysteria 2 installation complete!"
  else
    echo -e "${RED}❌ Error: Failed to install Hysteria 2. Please check your internet connection or the installation script.${RED}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return 1
  fi

  echo ""
  print_success "Hysteria 2 installation process finished."
  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}

# New function for Port Hopping Configuration
configure_port_hopping_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     🦘 Port Hopping Management${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  echo -e "  ${YELLOW}1)${RESET} ${GREEN}Enable Port Hopping${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${RED}Disable Port Hopping${RESET}"
  echo -e "  ${YELLOW}3)${RESET} ${WHITE}Back to previous menu${RESET}"
  echo ""
  read -p "👉 Your choice: " ph_choice
  echo ""

  if [[ "$ph_choice" == "3" ]]; then
    return
  fi

  local action_flag="-A"
  local action_verb="enabled"
  if [[ "$ph_choice" == "2" ]]; then
    action_flag="-D"
    action_verb="disabled"
  elif [[ "$ph_choice" != "1" ]]; then
    print_error "Invalid choice."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  # Detect Interface
  local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
  if [[ -z "$interface" ]]; then
      interface="eth0" # Fallback
  fi
  
  echo -e "${CYAN}Detected network interface: ${WHITE}$interface${RESET}"
  echo -e "${YELLOW}If this is incorrect, please enter the correct interface name (or press Enter to use detected):${RESET}"
  read -p "👉 " user_interface
  if [[ -n "$user_interface" ]]; then
      interface="$user_interface"
  fi
  echo ""

  echo -e "${CYAN}Select IP Version:${RESET}"
  echo -e "  ${YELLOW}1)${RESET} ${WHITE}IPv4${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${WHITE}IPv6${RESET}"
  echo -e "  ${YELLOW}3)${RESET} ${WHITE}IPv4 & IPv6${RESET}"
  read -p "👉 Your choice (1-3): " ip_ver_choice
  echo ""

  local start_port
  local end_port
  while true; do
      echo -e "👉 ${WHITE}Enter Start Port (e.g., 20000):${RESET} "
      read -p "" start_port
      if validate_port "$start_port"; then break; else print_error "Invalid port."; fi
  done

  while true; do
      echo -e "👉 ${WHITE}Enter End Port (e.g., 50000):${RESET} "
      read -p "" end_port
      if validate_port "$end_port" && (( end_port >= start_port )); then break; else print_error "Invalid port or less than start port."; fi
  done
  echo ""

  local target_port
  while true; do
      echo -e "👉 ${WHITE}Enter Target Hysteria Server Port (e.g., 443):${RESET} "
      read -p "" target_port
      if validate_port "$target_port"; then break; else print_error "Invalid port."; fi
  done
  echo ""

  # Execute Commands
  if [[ "$ip_ver_choice" == "1" || "$ip_ver_choice" == "3" ]]; then
      echo -e "${CYAN}Applying IPv4 rules...${RESET}"
      # iptables -t nat -A PREROUTING -i eth0 -p udp --dport 20000:50000 -j REDIRECT --to-ports 443
      if sudo iptables -t nat "$action_flag" PREROUTING -i "$interface" -p udp --dport "${start_port}:${end_port}" -j REDIRECT --to-ports "$target_port" 2>/dev/null; then
          print_success "IPv4 Port Hopping $action_verb."
      else
          print_error "Failed to apply IPv4 rule. (Maybe it doesn't exist or iptables is missing?)"
      fi
  fi

  if [[ "$ip_ver_choice" == "2" || "$ip_ver_choice" == "3" ]]; then
      echo -e "${CYAN}Applying IPv6 rules...${RESET}"
      # ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 20000:50000 -j REDIRECT --to-ports 443
      if sudo ip6tables -t nat "$action_flag" PREROUTING -i "$interface" -p udp --dport "${start_port}:${end_port}" -j REDIRECT --to-ports "$target_port" 2>/dev/null; then
          print_success "IPv6 Port Hopping $action_verb."
      else
          print_error "Failed to apply IPv6 rule. (Check if ip6tables is enabled/supported)"
      fi
  fi

  if [[ "$ph_choice" == "1" ]]; then
      echo ""
      echo -e "${YELLOW}⚠️  IMPORTANT: These rules are not persistent across reboots.${RESET}"
      echo -e "${YELLOW}   Please install 'iptables-persistent' or use a startup script to save them.${RESET}"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# New function for adding a Hysteria server
add_new_hysteria_server_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ➕ Add New Hysteria Server${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  # Check for hysteria executable
  if ! command -v hysteria &> /dev/null; then
    echo -e "${RED}❗ Hysteria executable (hysteria) not found.${RESET}"
    echo -e "${YELLOW}Please run 'Install Hysteria' option from the main menu first.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return
  fi

  local server_name
  while true; do
    echo -e "👉 ${CYAN}Enter server name (e.g., myserver, only alphanumeric, hyphens, underscores allowed):${RESET} "
    read -p "" server_name_input
    server_name=$(echo "$server_name_input" | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$server_name" ]]; then
      break
    else
      print_error "Server name cannot be empty!"
    fi
  done
  echo ""

  local service_name="hysteria-server-$server_name"
  local config_dir="$(pwd)/hysteria"
  local config_file_path="$config_dir/hysteria-server-$server_name.yaml"
  local service_file="/etc/systemd/system/${service_name}.service"

  if [ -f "$service_file" ]; then
    echo -e "${RED}❌ Service with this name already exists: $service_name.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$config_dir" # Ensure hysteria config directory exists

  echo -e "${CYAN}⚙️ Server Configuration:${RESET}"

  # --- Server Mode Selection ---
  local server_mode_choice
  local tls_cert_file=""
  local tls_key_file=""
  local sni_guard_config="" # Initialize as empty, will be set based on choice

  echo -e "${CYAN}Choose your server mode:${RESET}"
  echo -e "  ${YELLOW}1)${RESET} ${WHITE}Strict (Uses real Certbot certificates with SNI Guard)${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${WHITE}SNI (Uses real certificates for SNI obfuscation)${RESET}" # Updated description
  echo ""
  read -p "👉 Enter your choice (1-2): " server_mode_choice
  echo ""

  local certs_dir="/etc/letsencrypt/live"
  local self_signed_dir="$(pwd)/hysteria/certs/selfsigned"
  local available_certs=()
  local cert_paths=()
  local key_paths=()

  # Check LetsEncrypt Certs
  if [ -d "$certs_dir" ]; then
    while IFS= read -r domain; do
        if [[ -n "$domain" ]]; then
            available_certs+=("$domain (LetsEncrypt)")
            cert_paths+=("$certs_dir/$domain/fullchain.pem")
            key_paths+=("$certs_dir/$domain/privkey.pem")
        fi
    done < <(sudo find "$certs_dir" -maxdepth 1 -mindepth 1 -type d ! -name "README" -exec basename {} \;)
  fi

  # Check Self-Signed Certs
  if [ -d "$self_signed_dir" ]; then
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            available_certs+=("$name (Self-Signed)")
            cert_paths+=("$self_signed_dir/$name/fullchain.pem")
            key_paths+=("$self_signed_dir/$name/privkey.pem")
        fi
    done < <(find "$self_signed_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
  fi

  if [ ${#available_certs[@]} -eq 0 ]; then
    print_error "❌ No SSL certificates found (LetsEncrypt or Self-Signed)."
    print_error "   Please create one from the 'Certificate management' menu first."
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return
  fi

  echo -e "${CYAN}Available SSL Certificates:${RESET}"
  for i in "${!available_certs[@]}"; do
    echo -e "  ${YELLOW}$((i+1)))${RESET} ${WHITE}${available_certs[$i]}${RESET}"
  done

  local cert_choice
  while true; do
    echo -e "👉 ${WHITE}Select a certificate by number to use for Hysteria server:${RESET} "
    read -p "" cert_choice
    if [[ "$cert_choice" =~ ^[0-9]+$ ]] && [ "$cert_choice" -ge 1 ] && [ "$cert_choice" -le ${#available_certs[@]} ]; then
      break
    else
      print_error "Invalid selection. Please enter a valid number."
    fi
  done
  
  local selected_index=$((cert_choice-1))
  tls_cert_file="${cert_paths[$selected_index]}"
  tls_key_file="${key_paths[$selected_index]}"
  local selected_cert_name="${available_certs[$selected_index]}"

  if [ ! -f "$tls_cert_file" ] || [ ! -f "$tls_key_file" ]; then
    print_error "❌ Selected SSL certificate files not found: $tls_cert_file or $tls_key_file."
    print_error "   Server setup aborted."
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return
  fi
  print_success "Selected certificate: $selected_cert_name"

  case "$server_mode_choice" in
    1) # Strict Mode
      print_success "Strict server mode selected."
      sni_guard_config="  sniGuard: strict"
      ;;
    2) # SNI Mode
      print_success "SNI server mode selected (using real certificates)."
      sni_guard_config="  sniGuard: disable"
      ;;
    *)
      print_error "❌ Invalid server mode choice. Defaulting to Strict mode."
      server_mode_choice=1 # Fallback to strict
      sni_guard_config="  sniGuard: strict"
      ;;
  esac
  echo ""

  local listen_port
  while true; do
    echo -e "👉 ${WHITE}Enter listen port (1-65535, e.g., 443, 8443):${RESET} "
    read -p "" listen_port_input
    listen_port=${listen_port_input:-443}
    if validate_port "$listen_port"; then
      break
    else
      print_error "Invalid port number. Please enter a number between 1 and 65535."
    fi
  done
  echo ""

  local password
  while true; do
    echo -e "👉 ${WHITE}Enter password (e.g., strongpassword123):${RESET} "
    read -p "" password
    if [[ -n "$password" ]]; then
      break
    else
      print_error "Password cannot be empty!"
    fi
  done
  echo ""

  local obfuscation_enabled="false"
  local obfuscation_password=""
  local obfuscation_config="" # Initialize obfuscation_config
  echo -e "👉 ${WHITE}Do you want to enable Salamander obfuscation? (Y/n, default: n):${RESET} " # Changed to Salamander
  read -p "" obfuscation_choice_input
  obfuscation_choice_input=${obfuscation_choice_input:-n}

  if [[ "$obfuscation_choice_input" =~ ^[Yy]$ ]]; then
    obfuscation_enabled="true"
    while true; do
      echo -e "👉 ${WHITE}Enter Salamander obfuscation password:${RESET} " # Changed to Salamander
      read -p "" obfuscation_password
      if [[ -n "$obfuscation_password" ]]; then
        break
      else
        print_error "Salamander password cannot be empty!" # Changed to Salamander
      fi
    done
    obfuscation_config="obfs:
  type: salamander
  salamander:
    password: \"$obfuscation_password\"" # Changed type to salamander and password from user
    print_success "Salamander obfuscation enabled."
  else
    echo -e "${YELLOW}Salamander obfuscation is disabled.${RESET}" # Changed to Salamander
  fi
  echo ""

  # Masquerade for server
  local masquerade_config=""
  echo -e "👉 ${WHITE}Do you want to enable Masquerade? (Y/n, default: n)${RESET}"
  echo -e "   ${YELLOW}Note: If enabled, your tunnel port should be TLS (e.g., 443).${RESET}"
  read -p "" enable_masquerade_choice
  enable_masquerade_choice=${enable_masquerade_choice:-n}

  if [[ "$enable_masquerade_choice" =~ ^[Yy]$ ]]; then
    local masquerade_url
    while true; do
      echo -e "👉 ${WHITE}Enter Masquerade proxy URL (must start with https://, e.g., https://some.site.net):${RESET} "
      read -p "" masquerade_url
      if [[ "$masquerade_url" =~ ^https:// ]]; then
        break
      else
        print_error "Invalid URL. It must start with https://."
      fi
    done
    masquerade_config="
masquerade:
  proxy:
    url: \"$masquerade_url\"
    rewriteHost: true
    insecure: true"
    print_success "Masquerade enabled for server."
  else
    echo -e "${YELLOW}Masquerade is disabled for server.${RESET}"
  fi
  echo ""

  local upload_bandwidth=""
  local download_bandwidth=""
  local bandwidth_config="" # Initialize bandwidth_config
  echo -e "👉 ${WHITE}Set upload bandwidth limit in MB/s (optional, e.g., 10 for 10MB/s, leave empty for no limit):${RESET} "
  read -p "" upload_bandwidth
  echo -e "👉 ${WHITE}Set download bandwidth limit in MB/s (optional, e.g., 50 for 50MB/s, leave empty for no limit):${RESET} "
  read -p "" download_bandwidth
  echo ""

  if [[ -n "$upload_bandwidth" || -n "$download_bandwidth" ]]; then
    bandwidth_config="bandwidth:"
    if [[ -n "$upload_bandwidth" ]]; then
      bandwidth_config+="
  up: \"${upload_bandwidth}Mbps\"" # Hysteria expects Mbps
    fi
    if [[ -n "$download_bandwidth" ]]; then
      bandwidth_config+="
  down: \"${download_bandwidth}Mbps\"" # Hysteria expects Mbps
    fi
  fi

  # Ignore Client Bandwidth Hint
  local ignore_client_bandwidth_config=""
  echo -e "👉 ${WHITE}Do you want to ignore client bandwidth hints? (Y/n, default: n)${RESET}"
  echo -e "   ${YELLOW}Note: Useful to prevent clients from manipulating bandwidth limits.${RESET}"
  read -p "" ignore_client_bandwidth_choice
  ignore_client_bandwidth_choice=${ignore_client_bandwidth_choice:-n}

  if [[ "$ignore_client_bandwidth_choice" =~ ^[Yy]$ ]]; then
    ignore_client_bandwidth_config="ignoreClientBandwidth: true"
    print_success "Server will ignore client bandwidth hints."
  else
    echo -e "${YELLOW}Server will respect client bandwidth hints.${RESET}"
  fi
  echo ""

  # Speedtest for server
  local speedtest_config=""
  echo -e "👉 ${WHITE}Do you want to enable Speedtest? (Y/n, default: n):${RESET} "
  read -p "" enable_speedtest_choice
  enable_speedtest_choice=${enable_speedtest_choice:-n}

  if [[ "$enable_speedtest_choice" =~ ^[Yy]$ ]]; then
    speedtest_config="speedTest: true"
    print_success "Speedtest enabled for server."
  else
    echo -e "${YELLOW}Speedtest is disabled for server.${RESET}"
  fi
  echo ""


  # --- QUIC Parameters Selection ---
  local quic_initStreamReceiveWindow
  local quic_maxStreamReceiveWindow
  local quic_initConnReceiveWindow
  local quic_maxConnReceiveWindow
  local quic_maxIdleTimeout
  local quic_maxIncomingStreams
  local quic_disablePathMTUDiscovery

  echo -e "${CYAN}📊 QUIC Parameters Selection:${RESET}"
  echo -e "  ${YELLOW}1)${RESET} ${WHITE}Low Usage (Lower bandwidth, longer idle timeout)${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${WHITE}Medium Usage (Balanced, default values)${RESET}"
  echo -e "  ${YELLOW}3)${RESET} ${WHITE}High Usage (Higher bandwidth, shorter idle timeout, disables Path MTU Discovery)${RESET}"
  echo -e "  ${YELLOW}4)${RESET} ${WHITE}Custom Parameters${RESET}"
  echo ""
  read -p "👉 Enter your choice (1-4): " quic_choice
  echo ""

  case "$quic_choice" in
    1) # Low Usage
      quic_initStreamReceiveWindow="4194304" # 4MB
      quic_maxStreamReceiveWindow="4194304" # 4MB
      quic_initConnReceiveWindow="10485760" # 10MB
      quic_maxConnReceiveWindow="10485760" # 10MB
      quic_maxIdleTimeout="60s"
      quic_maxIncomingStreams="512"
      quic_disablePathMTUDiscovery="false"
      print_success "Low Usage QUIC parameters selected."
      ;;
    2) # Medium Usage (User provided defaults)
      quic_initStreamReceiveWindow="8388608" # 8MB
      quic_maxStreamReceiveWindow="8388608" # 8MB
      quic_initConnReceiveWindow="20971520" # 20MB
      quic_maxConnReceiveWindow="20971520" # 20MB
      quic_maxIdleTimeout="30s"
      quic_maxIncomingStreams="1024"
      quic_disablePathMTUDiscovery="false"
      print_success "Medium Usage QUIC parameters selected."
      ;;
    3) # High Usage
      quic_initStreamReceiveWindow="16777216" # 16MB
      quic_maxStreamReceiveWindow="16777216" # 16MB
      quic_initConnReceiveWindow="41943040" # 40MB
      quic_maxConnReceiveWindow="41943040" # 40MB
      quic_maxIdleTimeout="15s"
      quic_maxIncomingStreams="2048"
      quic_disablePathMTUDiscovery="true"
      print_success "High Usage QUIC parameters selected."
      ;;
    4) # Custom Parameters
      echo -e "${CYAN}Enter Custom QUIC Parameters:${RESET}"
      while true; do
        echo -e "👉 ${WHITE}initStreamReceiveWindow (bytes, e.g., 8388608):${RESET} "
        read -p "" quic_initStreamReceiveWindow
        if [[ "$quic_initStreamReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxStreamReceiveWindow (bytes, e.g., 8388608):${RESET} "
        read -p "" quic_maxStreamReceiveWindow
        if [[ "$quic_maxStreamReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}initConnReceiveWindow (bytes, e.g., 20971520):${RESET} "
        read -p "" quic_initConnReceiveWindow
        if [[ "$quic_initConnReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxConnReceiveWindow (bytes, e.g., 20971520):${RESET} "
        read -p "" quic_maxConnReceiveWindow
        if [[ "$quic_maxConnReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxIdleTimeout (e.g., 30s):${RESET} "
        read -p "" quic_maxIdleTimeout
        if [[ "$quic_maxIdleTimeout" =~ ^[0-9]+s$ ]]; then break; else print_error "Invalid input. Must be a number followed by 's' (e.g., 30s)."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxIncomingStreams (e.g., 1024):${RESET} "
        read -p "" quic_maxIncomingStreams
        if [[ "$quic_maxIncomingStreams" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}disablePathMTUDiscovery (true/false):${RESET} "
        read -p "" quic_disablePathMTUDiscovery
        if [[ "$quic_disablePathMTUDiscovery" =~ ^(true|false)$ ]]; then break; else print_error "Invalid input. Must be 'true' or 'false'."; fi
      done
      print_success "Custom QUIC parameters entered."
      ;;
    *)
      print_error "❌ Invalid choice. Defaulting to Medium Usage QUIC parameters."
      quic_initStreamReceiveWindow="8388608"
      quic_maxStreamReceiveWindow="8388608"
      quic_initConnReceiveWindow="20971520"
      quic_maxConnReceiveWindow="20971520"
      quic_maxIdleTimeout="30s"
      quic_maxIncomingStreams="1024"
      quic_disablePathMTUDiscovery="false"
      ;;
  esac
  echo ""

  local quic_config="
quic:
  initStreamReceiveWindow: $quic_initStreamReceiveWindow
  maxStreamReceiveWindow: $quic_maxStreamReceiveWindow
  initConnReceiveWindow: $quic_initConnReceiveWindow
  maxConnReceiveWindow: $quic_maxConnReceiveWindow
  maxIdleTimeout: $quic_maxIdleTimeout
  maxIncomingStreams: $quic_maxIncomingStreams
  disablePathMTUDiscovery: $quic_disablePathMTUDiscovery"

  # Create the Hysteria server config file (YAML)
  echo -e "${CYAN}📝 Creating hysteria-server-${server_name}.yaml configuration file...${RESET}"
  cat <<EOF > "$config_file_path"
listen: :$listen_port
auth:
  type: password
  password: "$password"
tls:
  cert: "$tls_cert_file"
  key: "$tls_key_file"
${sni_guard_config} # Conditionally add sniGuard
${obfuscation_config} # Optional obfuscation
${masquerade_config} # Optional masquerade
${bandwidth_config} # Optional bandwidth limits
${ignore_client_bandwidth_config} # Optional ignore client bandwidth
${speedtest_config} # Optional speedtest
${quic_config}
EOF
  print_success "hysteria-server-${server_name}.yaml created successfully at $config_file_path"

  # Create the systemd service file
  echo -e "${CYAN}🔧 Creating systemd service file for Hysteria server '$server_name'...${RESET}"
  cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=Hysteria Server - $server_name
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c "$config_file_path"
Restart=always
RestartSec=5
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${CYAN}🔧 Reloading systemd daemon...${RESET}"
  sudo systemctl daemon-reload

  echo -e "${CYAN}🚀 Enabling and starting Hysteria service '$service_name'...${RESET}"
  sudo systemctl enable "$service_name" > /dev/null 2>&1
  sudo systemctl start "$service_name" > /dev/null 2>&1

  print_success "Hysteria server '$server_name' started as $service_name"

  echo ""
  echo -e "${YELLOW}Do you want to view the logs for $service_name now? (y/N): ${RESET}"
  read -p "" view_logs_choice
  echo ""

  if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
    show_service_logs "$service_name"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}

# New function for adding a Hysteria client
add_new_hysteria_client_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ➕ Add New Hysteria Client${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  # Check for hysteria executable
  if ! command -v hysteria &> /dev/null; then
    echo -e "${RED}❗ Hysteria executable (hysteria) not found.${RESET}"
    echo -e "${YELLOW}Please run 'Install Hysteria' option from the main menu first.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return
  fi

  local client_name
  while true; do
    echo -e "👉 ${CYAN}Enter client name (e.g., myclient, alphanumeric, hyphens, underscores only):${RESET} "
    read -p "" client_name_input
    client_name=$(echo "$client_name_input" | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$client_name" ]]; then
      break
    else
      print_error "Client name cannot be empty!"
    fi
  done
  echo ""

  local service_name="hysteria-client-$client_name"
  local config_dir="$(pwd)/hysteria"
  local config_file_path="$config_dir/hysteria-client-$client_name.yaml"
  local service_file="/etc/systemd/system/${service_name}.service"

  if [ -f "$service_file" ]; then
    echo -e "${RED}❌ Service with this name already exists: $service_name.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$config_dir" # Ensure hysteria config directory exists

  echo -e "${CYAN}⚙️ Client Configuration:${RESET}"

  local server_address
  local server_port_string=""
  local is_port_hopping=false
  
  while true; do
    echo -e "👉 ${WHITE}Enter server address (IPv4/IPv6 or domain).${RESET}"
    echo -e "   ${YELLOW}For Single Port: Just enter the domain/IP (e.g., example.com)${RESET}"
    echo -e "   ${YELLOW}For Port Hopping: Enter domain:port-range (e.g., example.com:20000-50000)${RESET}"
    read -p "👉 " input_address
    
    # Check if input has port/range
    # Regex to capture host and port. 
    # Case 1: [IPv6]:port
    if [[ "$input_address" =~ ^\[(.*)\]:([0-9,-]+)$ ]]; then
        host_part="${BASH_REMATCH[1]}"
        port_part="${BASH_REMATCH[2]}"
        if validate_host "$host_part"; then
             server_address="[$host_part]" # Keep brackets for config
             server_port_string="$port_part"
             if [[ "$server_port_string" =~ [,-] ]]; then is_port_hopping=true; fi
             break
        else
             print_error "Invalid host part: $host_part"
        fi
    # Case 2: host:port (IPv4 or Domain)
    elif [[ "$input_address" =~ ^([^:]+):([0-9,-]+)$ ]]; then
        host_part="${BASH_REMATCH[1]}"
        port_part="${BASH_REMATCH[2]}"
        if validate_host "$host_part"; then
             server_address="$host_part"
             server_port_string="$port_part"
             if [[ "$server_port_string" =~ [,-] ]]; then is_port_hopping=true; fi
             break
        else
             print_error "Invalid host part: $host_part"
        fi
    # Case 3: Just host (IPv4, IPv6, Domain)
    elif validate_host "$input_address"; then
        if [[ "$input_address" =~ : ]]; then
            server_address="[$input_address]" # Add brackets for IPv6
        else
            server_address="$input_address"
        fi
        break
    else
        print_error "Invalid address format."
    fi
  done
  echo ""

  # If port was not provided in address, ask for it
  if [[ -z "$server_port_string" ]]; then
      while true; do
        echo -e "👉 ${WHITE}Enter server port(s).${RESET}"
        echo -e "   ${YELLOW}Single port (443), list (443,8443), or range (20000-50000):${RESET}"
        read -p "👉 " server_port_input
        if [[ "$server_port_input" =~ ^[0-9,-]+$ ]]; then
             server_port_string="$server_port_input"
             if [[ "$server_port_string" =~ [,-] ]]; then
                is_port_hopping=true
             fi
             break
        else
             print_error "Invalid port format."
        fi
      done
  fi
  echo ""

  local hop_interval_config=""
  if [[ "$is_port_hopping" == "true" ]]; then
      echo -e "${CYAN}Port Hopping detected!${RESET}"
      echo -e "👉 ${WHITE}Set Hop Interval in seconds (Default: 30).${RESET}"
      echo -e "   ${YELLOW}Enter 0 to disable hopping explicitly, or just press Enter for default (30s).${RESET}"
      read -p "👉 Enter interval (e.g., 30): " hop_interval_input
      
      # Set default to 30 if empty
      if [[ -z "$hop_interval_input" ]]; then
          hop_interval_input="30"
      fi

      if [[ "$hop_interval_input" =~ ^[0-9]+$ ]]; then
          hop_interval_config="transport:
  type: udp
  udp:
    hopInterval: ${hop_interval_input}s"
          print_success "Hop Interval set to ${hop_interval_input}s"
      else
          print_error "Invalid input. Defaulting to 30s."
          hop_interval_config="transport:
  type: udp
  udp:
    hopInterval: 30s"
      fi
  fi

  local password
  while true; do
    echo -e "👉 ${WHITE}Enter password for the Hysteria server:${RESET} "
    read -p "" password
    if [[ -n "$password" ]]; then
      break
    else
      print_error "Password cannot be empty!"
    fi
  done
  echo ""

  local obfs_config=""
  local obfuscation_choice_input
  echo -e "👉 ${WHITE}Do you want to enable Salamander obfuscation? (Y/n, default: n):${RESET} "
  read -p "" obfuscation_choice_input
  obfuscation_choice_input=${obfuscation_choice_input:-n}

  if [[ "$obfuscation_choice_input" =~ ^[Yy]$ ]]; then
    local salamander_password
    while true; do
      echo -e "👉 ${WHITE}Enter Salamander obfuscation password:${RESET} "
      read -p "" salamander_password
      if [[ -n "$salamander_password" ]]; then
        break
      else
        print_error "Salamander password cannot be empty!"
      fi
    done
    obfs_config="
obfs:
  type: salamander
  salamander:
    password: \"$salamander_password\"" # Changed to use user input
    print_success "Salamander obfuscation enabled."
  else
    echo -e "${YELLOW}Salamander obfuscation is disabled for client.${RESET}"
  fi
  echo ""

  # Masquerade for client
  local masquerade_config=""
  echo -e "👉 ${WHITE}Do you want to enable Masquerade? (Y/n, default: n)${RESET}"
  echo -e "   ${YELLOW}Note: If enabled, your tunnel port should be TLS (e.g., 443).${RESET}"
  read -p "" enable_masquerade_choice
  enable_masquerade_choice=${enable_masquerade_choice:-n}

  if [[ "$enable_masquerade_choice" =~ ^[Yy]$ ]]; then
    local masquerade_url
    while true; do
      echo -e "👉 ${WHITE}Enter Masquerade proxy URL (must start with https://, e.g., https://some.site.net):${RESET} "
      read -p "" masquerade_url
      if [[ "$masquerade_url" =~ ^https:// ]]; then
        break
      else
        print_error "Invalid URL. It must start with https://."
      fi
    done
    masquerade_config="
masquerade:
  proxy:
    url: \"$masquerade_url\"
    rewriteHost: true
    insecure: true"
    print_success "Masquerade enabled for client."
  else
    echo -e "${YELLOW}Masquerade is disabled for client.${RESET}"
  fi
  echo ""

  local tls_config=""
  local tls_insecure="true" # Always insecure for client
  local tls_sni_host=""

  echo -e "${CYAN}Client TLS Settings:${RESET}"
  echo -e "${WHITE}If your server is in Strict mode, you must enter your own domain.${RESET}"
  echo -e "${WHITE}If your server is in SNI mode, you can enter any hostname (e.g., cloudflare.com):${RESET}"
  while true; do
    echo -e "👉 ${WHITE}Enter the SNI hostname for the server:${RESET} "
    read -p "" tls_sni_host
    # The SNI hostname should ideally be a domain, not an IP.
    # We use validate_host here to ensure it's a valid host format,
    # but specifically check if it's NOT an IP address.
    if validate_host "$tls_sni_host" && ! [[ "$tls_sni_host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && ! [[ "$tls_sni_host" =~ ^([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){1,7}:(\b[0-9a-fA-F]{1,4}\b){1,7}$|^([0-9a-fA-F]{1,4}:){1,6}(:[0-9a-fA-F]{1,4}){1,2}$|^([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,3}$|^([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,4}$|^([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,5}$|^([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,6}$|^[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,7}|:)$|^::((:[0-9a-fA-F]{1,4}){1,7}|[0-9a-fA-F]{1,4})$|^[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$|^::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$ ]]; then
      break
    else
      print_error "Invalid SNI hostname. Please enter a valid domain name (not an IP address)."
    fi
  done
  print_success "SNI Host for TLS: $tls_sni_host"

  tls_config="
tls:
  insecure: $tls_insecure
  sni: \"$tls_sni_host\"
  alpn:
    - h3
    - h2
    - http/1.1"
  echo ""

  local network_protocol_choice
  echo -e "${CYAN}Select forwarding protocol (UDP, TCP, or Both):${RESET}"
  echo -e "  ${YELLOW}1)${RESET} ${WHITE}UDP${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${WHITE}TCP${RESET}"
  echo -e "  ${YELLOW}3)${RESET} ${WHITE}Both (Default)${RESET}"
  read -p "👉 Your choice (1-3, default: 3): " network_protocol_choice
  network_protocol_choice=${network_protocol_choice:-3}

  local forward_ports_input
  local udp_forwarding_content="" # Changed to hold only entries
  local tcp_forwarding_content="" # Changed to hold only entries

  while true; do
    echo -e "👉 ${WHITE}Enter forwarding ports separated by commas (e.g., 43070,53875):${RESET} "
    read -p "" forward_ports_input
    if [[ -n "$forward_ports_input" ]]; then
      # Validate each port in the comma-separated list
      local invalid_port_found=false
      IFS=',' read -ra ADDR <<< "$forward_ports_input"
      for p in "${ADDR[@]}"; do
        if ! validate_port "$p"; then
          print_error "Invalid port found: $p. Please enter valid ports between 1 and 65535."
          invalid_port_found=true
          break
        fi
      done
      if [ "$invalid_port_found" = false ]; then
        break
      fi
    else
      print_error "Forwarding ports cannot be empty!"
    fi
  done
  echo ""

  # Generate UDP forwarding content (entries only)
  if [[ "$network_protocol_choice" == "1" || "$network_protocol_choice" == "3" ]]; then
    IFS=',' read -ra ADDR <<< "$forward_ports_input"
    for p in "${ADDR[@]}"; do
      udp_forwarding_content+="
  - listen: 0.0.0.0:$p
    remote: '[::]:$p'
    timeout: 20s"
    done
  fi

  # Generate TCP forwarding content (entries only)
  if [[ "$network_protocol_choice" == "2" || "$network_protocol_choice" == "3" ]]; then
    IFS=',' read -ra ADDR <<< "$forward_ports_input"
    for p in "${ADDR[@]}"; do
      tcp_forwarding_content+="
  - listen: 0.0.0.0:$p
    remote: '[::]:$p'
    timeout: 20s"
    done
  fi

  # --- QUIC Parameters Selection (Copied from server setup) ---
  local quic_initStreamReceiveWindow
  local quic_maxStreamReceiveWindow
  local quic_initConnReceiveWindow
  local quic_maxConnReceiveWindow
  local quic_maxIdleTimeout
  local quic_maxIncomingStreams
  local quic_disablePathMTUDiscovery

  echo -e "${CYAN}📊 QUIC Parameters Selection:${RESET}"
  echo -e "  ${YELLOW}1)${RESET} ${WHITE}Low Usage (Lower bandwidth, longer idle timeout)${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${WHITE}Medium Usage (Balanced, default values)${RESET}"
  echo -e "  ${YELLOW}3)${RESET} ${WHITE}High Usage (Higher bandwidth, shorter idle timeout, disables Path MTU Discovery)${RESET}"
  echo -e "  ${YELLOW}4)${RESET} ${WHITE}Custom Parameters${RESET}"
  echo ""
  read -p "👉 Enter your choice (1-4): " quic_choice
  echo ""

  case "$quic_choice" in
    1) # Low Usage
      quic_initStreamReceiveWindow="4194304" # 4MB
      quic_maxStreamReceiveWindow="4194304" # 4MB
      quic_initConnReceiveWindow="10485760" # 10MB
      quic_maxConnReceiveWindow="10485760" # 10MB
      quic_maxIdleTimeout="60s"
      quic_maxIncomingStreams="512"
      quic_disablePathMTUDiscovery="false"
      print_success "Low Usage QUIC parameters selected."
      ;;
    2) # Medium Usage (User provided defaults)
      quic_initStreamReceiveWindow="8388608" # 8MB
      quic_maxStreamReceiveWindow="8388608" # 8MB
      quic_initConnReceiveWindow="20971520" # 20MB
      quic_maxConnReceiveWindow="20971520" # 20MB
      quic_maxIdleTimeout="30s"
      quic_maxIncomingStreams="1024"
      quic_disablePathMTUDiscovery="false"
      print_success "Medium Usage QUIC parameters selected."
      ;;
    3) # High Usage
      quic_initStreamReceiveWindow="16777216" # 16MB
      quic_maxStreamReceiveWindow="16777216" # 16MB
      quic_initConnReceiveWindow="41943040" # 40MB
      quic_maxConnReceiveWindow="41943040" # 40MB
      quic_maxIdleTimeout="15s"
      quic_maxIncomingStreams="2048"
      quic_disablePathMTUDiscovery="true"
      print_success "High Usage QUIC parameters selected."
      ;;
    4) # Custom Parameters
      echo -e "${CYAN}Enter Custom QUIC Parameters:${RESET}"
      while true; do
        echo -e "👉 ${WHITE}initStreamReceiveWindow (bytes, e.g., 8388608):${RESET} "
        read -p "" quic_initStreamReceiveWindow
        if [[ "$quic_initStreamReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxStreamReceiveWindow (bytes, e.g., 8388608):${RESET} "
        read -p "" quic_maxStreamReceiveWindow
        if [[ "$quic_maxStreamReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}initConnReceiveWindow (bytes, e.g., 20971520):${RESET} "
        read -p "" quic_initConnReceiveWindow
        if [[ "$quic_initConnReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxConnReceiveWindow (bytes, e.g., 20971520):${RESET} "
        read -p "" quic_maxConnReceiveWindow
        if [[ "$quic_maxConnReceiveWindow" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxIdleTimeout (e.g., 30s):${RESET} "
        read -p "" quic_maxIdleTimeout
        if [[ "$quic_maxIdleTimeout" =~ ^[0-9]+s$ ]]; then break; else print_error "Invalid input. Must be a number followed by 's' (e.g., 30s)."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}maxIncomingStreams (e.g., 1024):${RESET} "
        read -p "" quic_maxIncomingStreams
        if [[ "$quic_maxIncomingStreams" =~ ^[0-9]+$ ]]; then break; else print_error "Invalid input. Must be a number."; fi
      done
      while true; do
        echo -e "👉 ${WHITE}disablePathMTUDiscovery (true/false):${RESET} "
        read -p "" quic_disablePathMTUDiscovery
        if [[ "$quic_disablePathMTUDiscovery" =~ ^(true|false)$ ]]; then break; else print_error "Invalid input. Must be 'true' or 'false'."; fi
      done
      print_success "Custom QUIC parameters entered."
      ;;
    *)
      print_error "❌ Invalid choice. Defaulting to Medium Usage QUIC parameters."
      quic_initStreamReceiveWindow="8388608"
      quic_maxStreamReceiveWindow="8388608"
      quic_initConnReceiveWindow="20971520"
      quic_maxConnReceiveWindow="20971520"
      quic_maxIdleTimeout="30s"
      quic_maxIncomingStreams="1024"
      quic_disablePathMTUDiscovery="false"
      ;;
  esac
  echo ""

  local quic_config="
quic:
  initStreamReceiveWindow: $quic_initStreamReceiveWindow
  maxStreamReceiveWindow: $quic_maxStreamReceiveWindow
  initConnReceiveWindow: $quic_initConnReceiveWindow
  maxConnReceiveWindow: $quic_maxConnReceiveWindow
  maxIdleTimeout: $quic_maxIdleTimeout
  maxIncomingStreams: $quic_maxIncomingStreams
  disablePathMTUDiscovery: $quic_disablePathMTUDiscovery"


  # Create the Hysteria client config file (YAML)
  echo -e "${CYAN}📝 Creating hysteria-client-${client_name}.yaml configuration file...${RESET}"
  cat <<EOF > "$config_file_path"
server: "$server_address:$server_port_string" # Updated for Port Hopping support
auth: "$password" # Updated password format
$tls_config
$obfs_config
${masquerade_config} # Optional masquerade
${hop_interval_config} # Optional hopInterval for Port Hopping

$(if [[ -n "$udp_forwarding_content" ]]; then echo "udpForwarding:"; echo -e "$udp_forwarding_content"; echo ""; fi) # Always include header, add extra newline
$(if [[ -n "$tcp_forwarding_content" ]]; then echo "tcpForwarding:"; echo -e "$tcp_forwarding_content"; fi) # Always include header

${quic_config} # Added QUIC parameters to client config
EOF
  print_success "hysteria-client-${client_name}.yaml created successfully at $config_file_path"

  # Create the systemd service file
  echo -e "${CYAN}🔧 Creating systemd service file for Hysteria client '$client_name'...${RESET}"
  cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=Hysteria Client - $client_name
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria client -c "$config_file_path"
Restart=always
RestartSec=5
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${CYAN}🔧 Reloading systemd daemon...${RESET}"
  sudo systemctl daemon-reload

  echo -e "${CYAN}🚀 Enabling and starting Hysteria service '$service_name'...${RESET}"
  sudo systemctl enable "$service_name" > /dev/null 2>&1
  sudo systemctl start "$service_name" > /dev/null 2>&1

  print_success "Hysteria client '$client_name' started as $service_name"

  echo ""
  echo -e "${YELLOW}Do you want to view the logs for $service_name now? (y/N): ${RESET}"
  read -p "" view_logs_choice
  echo ""

  if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
    show_service_logs "$service_name"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}

# New function for running speedtest from client
speedtest_from_server_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ⚡ Speedtest from Server${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  echo -e "${YELLOW}⚠️ Note: Speedtest must be enabled on your Hysteria server for this to work.${RESET}"
  echo ""

  local config_dir="$(pwd)/hysteria"
  mapfile -t client_configs < <(find "$config_dir" -maxdepth 1 -type f -name "hysteria-client-*.yaml" -printf "%f\n" | sort)

  if [ ${#client_configs[@]} -eq 0 ]; then
    print_error "❌ No Hysteria client configuration files found in $config_dir."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 0
  fi

  echo -e "${CYAN}📋 Please select a client configuration file for speedtest:${RESET}"
  client_configs+=("Back to previous menu")
  select selected_config_file in "${client_configs[@]}"; do
    if [[ "$selected_config_file" == "Back to previous menu" ]]; then
      echo -e "${YELLOW}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_config_file" ]; then
      break
    else
      print_error "Invalid selection. Please enter a valid number."
    fi
  done
  echo ""

  local full_config_path="$config_dir/$selected_config_file"

  if [ -f "$full_config_path" ]; then
    echo -e "${CYAN}🚀 Running speedtest using client: ${WHITE}$selected_config_file${RESET}"
    echo ""
    /usr/local/bin/hysteria speedtest -c "$full_config_path"
    echo ""
    print_success "Speedtest completed."
  else
    print_error "❌ Configuration file not found: $full_config_path"
  fi
  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# New helper function for appending to YAML blocks
# This function is designed to append new entries to an existing YAML list block.
# It uses awk to find the block and insert the new content with correct indentation.
append_to_yaml_block() {
  local config_file="$1"
  local block_key="$2" # e.g., "udpForwarding" or "tcpForwarding"
  local new_entry_content="$3" # The multi-line YAML entry to add (e.g., "  - listen:...\n    remote:...")

  awk -v key="$block_key" -v entry="$new_entry_content" '
    BEGIN { in_block = 0; inserted = 0 }
    $0 ~ "^" key ":" { # Found the block header
      print; # Print the header
      in_block = 1;
      next;
    }
    in_block && /^[[:space:]]{2}[^[:space:]]/ { # Found a line with less indentation (end of block, e.g., next top-level key)
      if (!inserted) { # Only insert if not already inserted in this block
        print entry;
        inserted = 1;
      }
      print; # Print the current line (which is the start of the next block)
      in_block = 0; # Exit the block
      next;
    }
    {
      print; # Print current line
    }
    END {
      if (in_block && !inserted) { # If still in block at EOF and not inserted
        print entry; # Insert at the very end of the file
      }
    }
  ' "$config_file" > "${config_file}.tmp"
  mv "${config_file}.tmp" "$config_file"
}

# New helper function to insert a YAML block (header + first entry) if it's missing
# This function checks if a YAML block (e.g., 'udpForwarding:') exists.
# If not, it inserts the block header and the first entry before a specified pattern (e.g., 'quic:').
insert_yaml_block_if_missing() {
  local config_file="$1"
  local block_key="$2" # e.g., "udpForwarding"
  local new_entry_content="$3" # The multi-line YAML entry to add (e.g., "  - listen:...\n    remote:...")
  local insert_before_pattern="$4" # Regex pattern for key to insert before, e.g., "tcpForwarding|quic"

  if ! grep -q "^${block_key}:" "$config_file"; then
    local temp_file=$(mktemp)
    # The new block includes the header and the first entry
    local new_block_yaml="${block_key}:\n${new_entry_content}"
    local inserted_into_temp=false

    # Try to insert before insert_before_pattern
    awk -v insert_pattern="$insert_before_pattern" -v new_block="$new_block_yaml" '
      BEGIN { inserted = 0 }
      $0 ~ insert_pattern && !inserted {
        print new_block;
        print ""; # Add a blank line for separation after the new block
        inserted = 1;
      }
      { print }
    ' "$config_file" > "$temp_file"

    # If the block was not inserted (e.g., insert_before_pattern not found), append to end
    if [ "$(grep -c "^${block_key}:" "$temp_file")" -eq 0 ]; then
      echo -e "\n${new_block_yaml}" >> "$temp_file"
    fi
    mv "$temp_file" "$config_file"
    return 0 # Block was inserted
  fi
  return 1 # Block already exists
}


# New function to manage client forwarding ports
manage_client_ports_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ⚙️ Manage Client Ports${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  local config_dir="$(pwd)/hysteria"
  # Find all hysteria client config files
  mapfile -t client_configs < <(find "$config_dir" -maxdepth 1 -type f -name "hysteria-client-*.yaml" -printf "%f\n" | sort)

  if [ ${#client_configs[@]} -eq 0 ]; then
    print_error "❌ No Hysteria client configuration files found in $config_dir."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 0
  fi

  echo -e "${CYAN}📋 Please select a client to manage its ports:${RESET}"
  client_configs+=("Back to previous menu")
  select selected_config_file in "${client_configs[@]}"; do
    if [[ "$selected_config_file" == "Back to previous menu" ]]; then
      echo -e "${YELLOW}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_config_file" ]; then
      break
    else
      print_error "Invalid selection. Please enter a valid number."
    fi
  done
  echo ""

  local client_name=$(echo "$selected_config_file" | sed 's/hysteria-client-//' | sed 's/.yaml//')
  local config_file_path="$config_dir/$selected_config_file"
  local service_name="hysteria-client-$client_name"

  while true; do
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}     ⚙️ Manage Ports for '$client_name'${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""

    echo -e "${CYAN}Current Forwarding Ports:${RESET}"
    local udp_ports_array=()
    local tcp_ports_array=()

    # Extract UDP ports using awk for more robust block parsing
    mapfile -t udp_lines < <(awk '
      /^udpForwarding:/ {in_block=1; next}
      /^[^[:space:]]/ {in_block=0} # End of block if new top-level key
      in_block && /listen:/ {
        split($0, a, ":")
        port_num = a[length(a)] # Get the last part after the last colon
        sub(/^[[:space:]]+/, "", port_num) # Remove leading spaces
        print port_num
      }
    ' "$config_file_path")
    udp_ports_array=("${udp_lines[@]}")

    echo -e "  ${WHITE}UDP Ports:${RESET}"
    if [ ${#udp_ports_array[@]} -gt 0 ]; then
      for port in "${udp_ports_array[@]}"; do
        echo -e "    - ${YELLOW}$port${RESET}"
      done
    else
      echo -e "    ${RED}(None configured)${RESET}"
    fi

    # Extract TCP ports using awk
    mapfile -t tcp_lines < <(awk '
      /^tcpForwarding:/ {in_block=1; next}
      /^[^[:space:]]/ {in_block=0} # End of block if new top-level key
      in_block && /listen:/ {
        split($0, a, ":")
        port_num = a[length(a)] # Get the last part after the last colon
        sub(/^[[:space:]]+/, "", port_num) # Remove leading spaces
        print port_num
      }
    ' "$config_file_path")
    tcp_ports_array=("${tcp_lines[@]}")

    echo -e "  ${WHITE}TCP Ports:${RESET}"
    if [ ${#tcp_ports_array[@]} -gt 0 ]; then
      for port in "${tcp_ports_array[@]}"; do
        echo -e "    - ${YELLOW}$port${RESET}"
      done
    else
      echo -e "    ${RED}(None configured)${RESET}"
    fi
    echo ""

    echo "Select an action:"
    echo -e "  ${YELLOW}1)${RESET} ${WHITE}Reset and add new ports${RESET}" # New option
    echo -e "  ${YELLOW}2)${RESET} ${WHITE}Back to client management menu${RESET}" # Adjusted number
    echo ""
    read -p "👉 Your choice: " port_manage_choice
    echo ""

    case $port_manage_choice in
      1) # Reset and add new ports
        local new_ports_input
        while true; do
          echo -e "👉 ${WHITE}Enter new forwarding ports separated by commas (e.g., 43070,53875):${RESET} "
          read -p "" new_ports_input
          if [[ -n "$new_ports_input" ]]; then
            local invalid_port_found=false
            IFS=',' read -ra ADDR <<< "$new_ports_input"
            for p in "${ADDR[@]}"; do
              if ! validate_port "$p"; then
                print_error "Invalid port found: $p. Please enter valid ports between 1 and 65535."
                invalid_port_found=true
                break
              fi
            done
            if [ "$invalid_port_found" = false ]; then
              break
            fi
          else
            print_error "Forwarding ports cannot be empty!"
          fi
        done
        echo ""

        local new_protocol_choice
        echo -e "${CYAN}Select protocol for new ports:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} ${WHITE}UDP${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${WHITE}TCP${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Both${RESET}"
        read -p "👉 Your choice (1-3): " new_protocol_choice
        echo ""

        local temp_file=$(mktemp)
        cp "$config_file_path" "$temp_file"

        # Remove existing udpForwarding and tcpForwarding blocks
        # This sed command deletes lines from 'udpForwarding:' until the next top-level key or end of file.
        # It handles cases where the block might be at the end of the file.
        sed -i '/^udpForwarding:/,/^[[:alnum:]]/ { /^udpForwarding:/! { /^[[:alnum:]]/!d; }; }' "$temp_file"
        sed -i '/^tcpForwarding:/,/^[[:alnum:]]/ { /^tcpForwarding:/! { /^[[:alnum:]]/!d; }; }' "$temp_file"
        # The above sed commands are a bit complex to handle the end of file case.
        # A simpler approach for deletion might be:
        # sed -i '/^udpForwarding:/,${/^[[:alnum:]]/!d}' "$temp_file" # Deletes from udpForwarding to EOF
        # sed -i '/^tcpForwarding:/,${/^[[:alnum:]]/!d}' "$temp_file" # Deletes from tcpForwarding to EOF
        # This is more aggressive and might delete other blocks if they are after.
        # Let's use a safer approach to delete the block and its content.

        # A more robust way to delete a YAML block:
        # Use awk to print lines, skipping the target block.
        awk -v block1="udpForwarding" -v block2="tcpForwarding" '
          BEGIN { skip = 0 }
          $0 ~ "^" block1 ":" { skip = 1; next }
          $0 ~ "^" block2 ":" { skip = 1; next }
          skip == 1 && /^[[:alnum:]]/ { skip = 0 } # Stop skipping if a new top-level key is found
          skip == 0 { print }
        ' "$temp_file" > "${temp_file}.cleaned"
        mv "${temp_file}.cleaned" "$temp_file"

        local udp_new_content=""
        local tcp_new_content=""

        # Generate new UDP forwarding content
        if [[ "$new_protocol_choice" == "1" || "$new_protocol_choice" == "3" ]]; then
          IFS=',' read -ra ADDR <<< "$new_ports_input"
          for p in "${ADDR[@]}"; do
            udp_new_content+="  - listen: 0.0.0.0:$p\n    remote: '[::]:$p'\n    timeout: 20s\n"
          done
          udp_new_content="udpForwarding:\n${udp_new_content}"
        fi

        # Generate new TCP forwarding content
        if [[ "$new_protocol_choice" == "2" || "$new_protocol_choice" == "3" ]]; then
          IFS=',' read -ra ADDR <<< "$new_ports_input"
          for p in "${ADDR[@]}"; do
            tcp_new_content+="  - listen: 0.0.0.0:$p\n    remote: '[::]:$p'\n    timeout: 20s\n"
          done
          tcp_new_content="tcpForwarding:\n${tcp_new_content}"
        fi

        local insert_point=$(grep -n "^quic:" "$temp_file" | head -n 1 | cut -d: -f1)
        if [[ -z "$insert_point" ]]; then
            # If 'quic:' block not found, append to the end
            if [[ -n "$udp_new_content" ]]; then
                echo -e "\n${udp_new_content}" >> "$temp_file"
            fi
            if [[ -n "$tcp_new_content" ]]; then
                echo -e "\n${tcp_new_content}" >> "$temp_file"
            fi
        else
            # Insert before 'quic:' block
            local insert_line_num=$((insert_point - 1))
            if [[ -n "$tcp_new_content" ]]; then
                sed -i "${insert_line_num}i\\
${tcp_new_content}" "$temp_file"
                insert_line_num=$((insert_line_num)) # Adjust if UDP is also inserted
            fi
            if [[ -n "$udp_new_content" ]]; then
                sed -i "${insert_line_num}i\\
${udp_new_content}" "$temp_file"
            fi
        fi

        mv "$temp_file" "$config_file_path"
        print_success "Ports reset and added successfully."
        echo -e "${CYAN}Restarting Hysteria client '$client_name' to apply changes...${RESET}"
        sudo systemctl restart "$service_name" > /dev/null 2>&1
        print_success "Client service restarted."
        ;;
      2) # Back to client management menu (adjusted number)
        echo -e "${YELLOW}Returning to client management menu...${RESET}"
        break
        ;;
      *)
        echo -e "${RED}❌ Invalid option.${RESET}"
        ;;
    esac
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${RESET}"
    read -p ""
  done
}


# --- Initial Setup Function ---
# This function performs one-time setup tasks like installing dependencies
# and creating the 'trust' command symlink.
perform_initial_setup() {
  # Check if initial setup has already been performed
  if [ -f "$SETUP_MARKER_FILE" ]; then
    echo -e "${YELLOW}Initial setup already performed. Skipping prerequisites installation.${RESET}"
    return 0 # Exit successfully
  fi

  echo -e "${CYAN}Performing initial setup (installing dependencies)...${RESET}"

  # Install required tools
  echo -e "${CYAN}Updating package lists and installing dependencies...${RESET}"
  sudo apt update
  # Removed rustc and cargo from apt install list
  sudo apt install -y build-essential curl pkg-config libssl-dev git figlet certbot cron

  # Removed Rust-specific checks and installations
  # The script now assumes Hysteria's own installation handles its dependencies.

  sudo mkdir -p "$(dirname "$SETUP_MARKER_FILE")" # Ensure directory exists for marker file
  sudo touch "$SETUP_MARKER_FILE" # Create marker file only if all initial setup steps succeed
  print_success "Initial setup complete."
  echo ""
  return 0
}

# --- New: Function to get a new SSL certificate using Certbot ---
get_new_certificate_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ➕ Get New SSL Certificate${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  echo -e "${CYAN}🌐 Domain and Email for SSL Certificate:${RESET}"
  echo -e "  (e.g., yourdomain.com)"
  
  local domain
  while true; do
    echo -e "👉 ${WHITE}Please enter your domain:${RESET} "
    read -p "" domain
    if validate_host "$domain"; then
      break
    else
      print_error "Invalid domain or IP address format. Please try again."
    fi
  done
  echo ""

  local email
  while true; do
    echo -e "👉 ${WHITE}Please enter your email:${RESET} "
    read -p "" email
    if validate_email "$email"; then
      break
    else
      print_error "Invalid email format. Please try again."
    fi
  done
  echo ""

  local cert_path="/etc/letsencrypt/live/$domain"

  if [ -d "$cert_path" ]; then
    print_success "SSL certificate for $domain already exists. Skipping Certbot."
  else
    echo -e "${CYAN}🔐 Requesting SSL certificate with Certbot...${RESET}"
    echo -e "${YELLOW}Ensure port 80 is open and not in use by another service.${RESET}"
    if sudo certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "$email"; then
      print_success "SSL certificate obtained successfully for $domain."
    else
      print_error "❌ Failed to obtain SSL certificate for $domain. Check Certbot logs for details."
      print_error "   Ensure your domain points to this server and port 80 is open."
    fi
  fi
  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# --- New: Function to delete existing SSL certificates ---
delete_certificates_action() {
  clear
  echo ""
  draw_line "$RED" "=" 40
  echo -e "${RED}     🗑️ Delete SSL Certificates${RESET}"
  draw_line "$RED" "=" 40
  echo ""

  echo -e "${CYAN}🔍 Searching for existing SSL certificates...${RESET}"
  # Find directories under /etc/letsencrypt/live/ that are not 'README'
  mapfile -t cert_domains < <(sudo find /etc/letsencrypt/live -maxdepth 1 -mindepth 1 -type d ! -name "README" -exec basename {} \;)

  if [ ${#cert_domains[@]} -eq 0 ]; then
    print_error "No SSL certificates found to delete."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 0
  fi

  echo -e "${CYAN}📋 Please select a certificate to delete:${RESET}"
  # Add a "Back to previous menu" option
  cert_domains+=("Back to previous menu")
  select selected_domain in "${cert_domains[@]}"; do
    if [[ "$selected_domain" == "Back to previous menu" ]]; then
      echo -e "${YELLOW}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_domain" ]; then
      break
    else
      print_error "Invalid selection. Please enter a valid number."
    fi
  done
  echo ""

  if [[ -z "$selected_domain" ]]; then
    print_error "No certificate selected. Aborting deletion."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 0
  fi

  echo -e "${RED}⚠️ Are you sure you want to delete the certificate for '$selected_domain'? (y/N): ${RESET}"
  read -p "" confirm_delete
  echo ""

  if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}🗑️ Deleting certificate for '$selected_domain' using Certbot...${RESET}"
    if sudo certbot delete --cert-name "$selected_domain"; then
      print_success "Certificate for '$selected_domain' deleted successfully."
    else
      print_error "❌ Failed to delete certificate for '$selected_domain'. Check Certbot logs."
    fi
  else
    echo -e "${YELLOW}Deletion cancelled for '$selected_domain'.${RESET}"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Function to generate a self-signed certificate
generate_self_signed_cert_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     📝 Generate Self-Signed Certificate${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""
  
  echo -e "${YELLOW}⚠️  WARNING: Self-signed certificates only work with SNI Mode!${RESET}"
  echo -e "${YELLOW}    Do not use this for Strict Mode.${RESET}"
  echo ""

  local cert_name
  while true; do
    echo -e "👉 ${WHITE}Enter a name for this certificate (e.g., my-self-signed):${RESET} "
    read -p "" cert_name
    # Sanitize input
    cert_name=$(echo "$cert_name" | tr -cd '[:alnum:]_-')
    if [[ -n "$cert_name" ]]; then
      break
    else
      print_error "Certificate name cannot be empty."
    fi
  done
  echo ""

  local cert_dir="$(pwd)/hysteria/certs/selfsigned/$cert_name"
  if [ -d "$cert_dir" ]; then
    print_error "A certificate with this name already exists."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$cert_dir"

  echo -e "${CYAN}Generating self-signed certificate...${RESET}"
  
  # Generate key and cert
  # using the name as CN
  if openssl req -x509 -newkey rsa:2048 -keyout "$cert_dir/privkey.pem" -out "$cert_dir/fullchain.pem" -sha256 -days 3650 -nodes -subj "/CN=$cert_name" 2>/dev/null; then
    print_success "Self-signed certificate generated successfully."
    echo -e "   Path: ${WHITE}$cert_dir${RESET}"
  else
    print_error "Failed to generate certificate. Please check if openssl is installed."
    rm -rf "$cert_dir" # Cleanup
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Function to delete self-signed certificates
delete_self_signed_cert_action() {
  clear
  echo ""
  draw_line "$RED" "=" 40
  echo -e "${RED}     🗑️ Delete Self-Signed Certificate${RESET}"
  draw_line "$RED" "=" 40
  echo ""

  local cert_base_dir="$(pwd)/hysteria/certs/selfsigned"
  
  if [ ! -d "$cert_base_dir" ]; then
     print_error "No self-signed certificates found."
     echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
     read -p ""
     return
  fi

  mapfile -t cert_names < <(find "$cert_base_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)

  if [ ${#cert_names[@]} -eq 0 ]; then
    print_error "No self-signed certificates found."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  echo -e "${CYAN}📋 Please select a certificate to delete:${RESET}"
  cert_names+=("Back to previous menu")
  select selected_cert in "${cert_names[@]}"; do
    if [[ "$selected_cert" == "Back to previous menu" ]]; then
      return
    elif [ -n "$selected_cert" ]; then
      break
    else
      print_error "Invalid selection."
    fi
  done

  echo -e "${RED}⚠️ Are you sure you want to delete '$selected_cert'? (y/N): ${RESET}"
  read -p "" confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
      rm -rf "$cert_base_dir/$selected_cert"
      print_success "Certificate deleted."
  else
      echo -e "${YELLOW}Cancelled.${RESET}"
  fi
  
  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Self-signed certificate menu
self_signed_certificate_menu() {
  while true; do
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}     📝 Self-Signed Certificates${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    echo -e "  ${YELLOW}1)${RESET} ${WHITE}Generate new certificate${RESET}"
    echo -e "  ${YELLOW}2)${RESET} ${WHITE}Delete certificate${RESET}"
    echo -e "  ${YELLOW}3)${RESET} ${WHITE}Back to previous menu${RESET}"
    echo ""
    read -p "👉 Your choice: " choice
    case $choice in
      1) generate_self_signed_cert_action ;;
      2) delete_self_signed_cert_action ;;
      3) break ;;
      *) print_error "Invalid option." ;;
    esac
  done
}

# --- New: Certificate Management Menu Function ---
certificate_management_menu() {
  while true; do
    clear
    echo ""
    draw_line "$YELLOW" "=" 40
    echo -e "${CYAN}     🔐 Certificate Management${RESET}"
    draw_line "$YELLOW" "=" 40
    echo ""
    echo -e "  ${YELLOW}1)${RESET} ${WHITE}Get new certificate${RESET}"
    echo -e "  ${YELLOW}2)${RESET} ${WHITE}Delete certificates${RESET}"
    echo -e "  ${YELLOW}3)${RESET} ${WHITE}Self signed certificate${RESET}"
    echo -e "  ${YELLOW}4)${RESET} ${WHITE}Back to main menu${RESET}"
    echo ""
    draw_line "$YELLOW" "-" 40
    echo -e "👉 ${CYAN}Your choice:${RESET} "
    read -p "" cert_choice
    echo ""

    case $cert_choice in
      1)
        get_new_certificate_action
        ;;
      2)
        delete_certificates_action
        ;;
      3)
        self_signed_certificate_menu
        ;;
      4)
        echo -e "${YELLOW}Returning to main menu...${RESET}"
        break # Break out of this while loop to return to main menu
        ;;
      *)
        echo -e "${RED}❌ Invalid option.${RESET}"
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${RESET}"
        read -p ""
        ;;
    esac
  done
}

# --- New function to check Hysteria installation status ---
check_hysteria_installation_status() {
  if command -v hysteria &> /dev/null; then
    echo -e "${GREEN}Installed ✅${RESET}"
  else
    echo -e "${RED}Not Installed ❌${RESET}"
  fi
}

# --- Main Script Execution ---
set -e # Exit immediately if a command exits with a non-zero status

# Perform initial setup (will run only once)
perform_initial_setup || { echo "Initial setup failed. Exiting."; exit 1; }

# Removed Rust readiness check as it's no longer installed by this script's initial setup.
# The Hysteria installation script is responsible for its own dependencies.

while true; do
  # Clear terminal and show logo
  clear
  echo -e "${CYAN}"
  figlet -f slant "HPulse Tunnel" # Changed to Hysteria
  echo -e "${CYAN}"
  draw_line "$CYAN" "=" 80 # Decorative line
  echo ""
  echo -e "Developed by ErfanXRay => ${BOLD_GREEN}https://github.com/Erfan-XRay/HPulse${RESET}"
  echo -e "Telegram Channel => ${BOLD_GREEN}@Erfan_XRay${RESET}"
  echo -e "Tunnel script based on ${CYAN}Hysteria 2${RESET}" # Generic description
  echo ""
  # Get server IP addresses
  SERVER_IPV4=$(hostname -I | awk '{print $1}')
  # SERVER_IPV6=$(hostname -I | awk '{print $2}') # This might be empty if no IPv6


  draw_line "$CYAN" "=" 40 # Decorative line
  echo -e "${CYAN}     🌐 Server Information${RESET}" # Changed to English
  draw_line "$CYAN" "=" 40 # Decorative line
  echo -e "  ${WHITE}IPv4 Address: ${YELLOW}$SERVER_IPV4${RESET}" # Changed to English
  # Replaced IPv6 with Hysteria Installation Status
  echo -e "  ${WHITE}Hysteria Status: $(check_hysteria_installation_status)${RESET}"
  echo -e "  ${WHITE}Script Version: ${YELLOW}$SCRIPT_VERSION${RESET}" # Changed to English
  draw_line "$CYAN" "=" 40 # Decorative line
  echo "" # Added for spacing

  # Menu
  echo "Select an option:"
  echo ""
  echo -e "${MAGENTA}1) Install Hysteria${RESET}"
  echo -e "${CYAN}2) Hysteria tunnel management${RESET}"
  echo -e "${YELLOW}3) Certificate management${RESET}" # Re-numbered from 4 to 3
  echo -e "${RED}4) Uninstall Hysteria and cleanup${RESET}" # Re-numbered from 5 to 4
  echo -e "${WHITE}5) Exit${RESET}" # Re-numbered from 6 to 5
  echo ""
  read -p "👉 Your choice: " choice

  case $choice in
    1)
      install_hysteria_action
      ;;
    2) # Hysteria tunnel management
      while true; do
        clear
        echo ""
        draw_line "$CYAN" "=" 40
        echo -e "${CYAN}     🌐 Hysteria Tunnel Management${RESET}"
        draw_line "$CYAN" "=" 40
        echo ""
        echo -e "  ${YELLOW}1)${RESET} ${MAGENTA}Server (Kharej)${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${BLUE}Client (Iran)${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Return to main menu${RESET}"
        echo ""
        draw_line "$CYAN" "-" 40
        echo -e "👉 ${CYAN}Your choice:${RESET} "
        read -p "" hysteria_tunnel_choice
        echo ""

        case $hysteria_tunnel_choice in
          1) # Hysteria Server Management
            while true; do
              clear
              echo ""
              draw_line "$CYAN" "=" 40
              echo -e "${CYAN}     🔧 Hysteria Server Management${RESET}"
              draw_line "$CYAN" "=" 40
              echo ""
              echo -e "  ${YELLOW}1)${RESET} ${WHITE}Add new Hysteria server${RESET}"
              echo -e "  ${YELLOW}2)${RESET} ${WHITE}Show Hysteria server logs${RESET}"
              echo -e "  ${YELLOW}3)${RESET} ${WHITE}Delete a Hysteria server${RESET}"
              echo -e "  ${YELLOW}4)${RESET} ${MAGENTA}Schedule Hysteria server restart${RESET}"
              echo -e "  ${YELLOW}5)${RESET} ${RED}Delete scheduled restart${RESET}"
              echo -e "  ${YELLOW}6)${RESET} ${GREEN}Port Hopping Management${RESET}"
              echo -e "  ${YELLOW}7)${RESET} ${WHITE}Back to previous menu${RESET}"
              echo ""
              draw_line "$CYAN" "-" 40
              echo -e "👉 ${CYAN}Your choice:${RESET} "
              read -p "" hysteria_srv_choice
              echo ""

              case $hysteria_srv_choice in
                1)
                  add_new_hysteria_server_action
                  ;;
                2)
                  clear
                  echo ""
                  draw_line "$CYAN" "=" 40
                  echo -e "${CYAN}     📊 Hysteria Server Logs${RESET}"
                  draw_line "$CYAN" "=" 40
                  echo ""
                  echo -e "${CYAN}🔍 Searching for Hysteria servers ...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'hysteria-server-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${RED}❌ No Hysteria servers found.${RESET}"
                  else
                    echo -e "${CYAN}📋 Please select a service to see log:${RESET}"
                    services+=("Back to previous menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to previous menu" ]]; then
                        echo -e "${YELLOW}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        show_service_logs "$selected_service"
                        break
                      else
                        echo -e "${RED}⚠️ Invalid selection. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
                  read -p ""
                  ;;
                3)
                  clear
                  echo ""
                  draw_line "$CYAN" "=" 40
                  echo -e "${CYAN}     🗑️ Delete Hysteria Server${RESET}"
                  draw_line "$CYAN" "=" 40
                  echo ""
                  echo -e "${CYAN}🔍 Searching for Hysteria servers ...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'hysteria-server-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${RED}❌ No Hysteria servers found.${RESET}"
                  else
                    echo -e "${CYAN}📋 Please select a service to delete:${RESET}"
                    services+=("Back to previous menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to previous menu" ]]; then
                        echo -e "${YELLOW}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        service_file="/etc/systemd/system/${selected_service}.service"
                        config_file_to_delete="$(pwd)/hysteria/${selected_service}.yaml" # Construct YAML file path
                        
                        echo -e "${YELLOW}🛑 Stopping $selected_service...${RESET}"
                        sudo systemctl stop "$selected_service" > /dev/null 2>&1
                        sudo systemctl disable "$selected_service" > /dev/null 2>&1
                        sudo rm -f "$service_file" > /dev/null 2>&1
                        sudo systemctl daemon-reload > /dev/null 2>&1
                        print_success "Hysteria server '$selected_service' deleted."
                        
                        # Remove the YAML configuration file
                        if [ -f "$config_file_to_delete" ]; then
                            echo "🗑️ Removing configuration file: $config_file_to_delete..."
                            rm -f "$config_file_to_delete"
                            print_success "Configuration file removed."
                        else
                            echo "⚠️ Configuration file not found: $config_file_to_delete. Skipping deletion."
                        fi

                        (sudo crontab -l 2>/dev/null | grep -v "# Hysteria automated restart for $selected_service$") | sudo crontab -
                        print_success "Cron jobs for '$selected_service' removed."
                        # Also remove faketls directory if it exists for this server
                        server_config_dir="$(pwd)/hysteria"
                        if [ -d "$server_config_dir/faketls" ]; then
                            echo "🗑️ Removing fake TLS certificates for '$selected_service'..."
                            rm -rf "$server_config_dir/faketls"
                            print_success "Fake TLS certificates removed."
                        fi
                        break
                      else
                        echo -e "${RED}⚠️ Invalid selection. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
                  read -p ""
                  ;;
                4) # Schedule Hysteria server restart
                  clear
                  echo ""
                  draw_line "$CYAN" "=" 40
                  echo -e "${CYAN}     ⏰ Schedule Hysteria Server Restart${RESET}"
                  draw_line "$CYAN" "=" 40
                  echo ""
                  echo -e "${CYAN}🔍 Searching for Hysteria servers ...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'hysteria-server-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${RED}❌ No Hysteria servers found to schedule. Please add a server first.${RESET}"
                    echo ""
                    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
                    read -p ""
                  else
                    echo -e "${CYAN}📋 Please select which Hysteria server service to schedule for restart:${RESET}"
                    services+=("Back to previous menu")
                    select selected_server_service in "${services[@]}"; do
                      if [[ "$selected_server_service" == "Back to previous menu" ]]; then
                        echo -e "${YELLOW}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_server_service" ]; then
                        reset_timer "$selected_server_service"
                        break
                      else
                        echo -e "${RED}⚠️ Invalid selection. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  ;;
                5)
                  delete_cron_job_action
                  ;;
                6)
                  configure_port_hopping_action
                  ;;
                7)
                  echo -e "${YELLOW}Returning to previous menu...${RESET}"
                  break # Break out of this while loop to return to Hysteria Tunnel Management
                  ;;
                *)
                  echo -e "${RED}❌ Invalid option.${RESET}"
                  echo ""
                  echo -e "${YELLOW}Press Enter to continue...${RESET}"
                  read -p ""
                  ;;
              esac
            done
            ;;
          2) # Hysteria Client Management
            while true; do
              clear
              echo ""
              draw_line "$CYAN" "=" 40
              echo -e "${CYAN}     📡 Hysteria Client Management${RESET}"
              draw_line "$CYAN" "=" 40
              echo ""
              echo -e "  ${YELLOW}1)${RESET} ${WHITE}Add new Hysteria client${RESET}"
              echo -e "  ${YELLOW}2)${RESET} ${WHITE}Show Hysteria client logs${RESET}"
              echo -e "  ${YELLOW}3)${RESET} ${WHITE}Delete a Hysteria client${RESET}"
              echo -e "  ${YELLOW}4)${RESET} ${BLUE}Schedule Hysteria client restart${RESET}"
              echo -e "  ${YELLOW}5)${RESET} ${RED}Delete scheduled restart${RESET}"
              echo -e "  ${YELLOW}6)${RESET} ${WHITE}Speedtest from server${RESET}"
              echo -e "  ${YELLOW}7)${RESET} ${WHITE}Manage Client Ports${RESET}" # New option
              echo -e "  ${YELLOW}8)${RESET} ${WHITE}Back to previous menu${RESET}" # Adjusted number
              echo ""
              draw_line "$CYAN" "-" 40
              echo -e "👉 ${CYAN}Your choice:${RESET} "
              read -p "" hysteria_client_choice
              echo ""

              case $hysteria_client_choice in
                1)
                  add_new_hysteria_client_action
                  ;;
                2)
                  clear
                  echo ""
                  draw_line "$CYAN" "=" 40
                  echo -e "${CYAN}     📊 Hysteria Client Logs${RESET}"
                  draw_line "$CYAN" "=" 40
                  echo ""
                  echo -e "${CYAN}🔍 Searching for Hysteria clients ...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'hysteria-client-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${RED}❌ No Hysteria clients found.${RESET}"
                  else
                    echo -e "${CYAN}📋 Please select a service to see log:${RESET}"
                    services+=("Back to previous menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to previous menu" ]]; then
                        echo -e "${YELLOW}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        show_service_logs "$selected_service"
                        break
                      else
                        echo -e "${RED}⚠️ Invalid selection. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
                  read -p ""
                  ;;
                3)
                  clear
                  echo ""
                  draw_line "$CYAN" "=" 40
                  echo -e "${CYAN}     🗑️ Delete Hysteria Client${RESET}"
                  draw_line "$CYAN" "=" 40
                  echo ""
                  echo -e "${CYAN}🔍 Searching for Hysteria clients ...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'hysteria-client-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${RED}❌ No Hysteria clients found.${RESET}"
                  else
                    echo -e "${CYAN}📋 Please select a service to delete:${RESET}"
                    services+=("Back to previous menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to previous menu" ]]; then
                        echo -e "${YELLOW}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        service_file="/etc/systemd/system/${selected_service}.service"
                        config_file_to_delete="$(pwd)/hysteria/${selected_service}.yaml" # Construct YAML file path

                        echo -e "${YELLOW}🛑 Stopping $selected_service...${RESET}"
                        sudo systemctl stop "$selected_service" > /dev/null 2>&1
                        sudo systemctl disable "$selected_service" > /dev/null 2>&1
                        sudo rm -f "$service_file" > /dev/null 2>&1
                        sudo systemctl daemon-reload > /dev/null 2>&1
                        print_success "Hysteria client '$selected_service' deleted."
                        
                        # Remove the YAML configuration file
                        if [ -f "$config_file_to_delete" ]; then
                            echo "🗑️ Removing configuration file: $config_file_to_delete..."
                            rm -f "$config_file_to_delete"
                            print_success "Configuration file removed."
                        else
                            echo "⚠️ Configuration file not found: $config_file_to_delete. Skipping deletion."
                        fi

                        (sudo crontab -l 2>/dev/null | grep -v "# Hysteria automated restart for $selected_service$") | sudo crontab -
                        print_success "Cron jobs for '$selected_service' removed."
                        break
                      else
                        echo -e "${RED}⚠️ Invalid selection. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
                  read -p ""
                  ;;
                4) # Schedule Hysteria client restart
                  clear
                  echo ""
                  draw_line "$CYAN" "=" 40
                  echo -e "${CYAN}     ⏰ Schedule Hysteria Client Restart${RESET}"
                  draw_line "$CYAN" "=" 40
                  echo ""
                  echo -e "${CYAN}🔍 Searching for Hysteria clients ...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'hysteria-client-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${RED}❌ No Hysteria clients found to schedule. Please add a client first.${RESET}"
                    echo ""
                    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
                    read -p ""
                  else
                    echo -e "${CYAN}📋 Please select which Hysteria client service to schedule for restart:${RESET}"
                    services+=("Back to previous menu")
                    select selected_client_service in "${services[@]}"; do
                      if [[ "$selected_client_service" == "Back to previous menu" ]]; then
                        echo -e "${YELLOW}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_client_service" ]; then
                        reset_timer "$selected_client_service"
                        break
                      else
                        echo -e "${RED}⚠️ Invalid selection. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  ;;
                5)
                  delete_cron_job_action
                  ;;
                6) # New Speedtest option
                  speedtest_from_server_action
                  ;;
                7) # Manage Client Ports
                  manage_client_ports_action
                  ;;
                8) # Adjusted number for Back to previous menu
                  echo -e "${YELLOW}Returning to previous menu...${RESET}"
                  break # Break out of this while loop to return to Hysteria Tunnel Management
                  ;;
                *)
                  echo -e "${RED}❌ Invalid option.${RESET}"
                  echo ""
                  echo -e "${YELLOW}Press Press Enter to continue...${RESET}"
                  read -p ""
                  ;;
              esac
            done
            ;;
          3)
            echo -e "${YELLOW}Returning to main menu...${RESET}"
            break # Break out of this while loop to return to main menu
            ;;
          *)
            echo -e "${RED}❌ Invalid option.${RESET}"
            echo ""
            echo -e "${YELLOW}Press Enter to continue...${RESET}"
            read -p ""
            ;;
        esac
      done
      ;;
    3) # Certificate Management option (re-numbered)
      certificate_management_menu
      ;;
    4) # Uninstall Hysteria and cleanup (re-numbered and text updated)
      uninstall_hysteria_and_direct_action
      ;;
    5) # Exit (re-numbered)
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Invalid choice. Exiting.${RESET}"
      echo ""
      echo -e "${YELLOW}Press Enter to continue...${RESET}"
      read -p ""
    ;;
  esac
  echo ""
done
