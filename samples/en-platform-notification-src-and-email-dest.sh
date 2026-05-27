#!/bin/bash

# =================================================
# IBM Cloud Platform Notifications to Event Notifications Integration Script
# =================================================
# This script automates the setup of IBM Cloud Event Notifications to receive
# platform notifications from the IBM Cloud Notification Distribution List.
#
# WHAT THIS SCRIPT CREATES:
# 1. Event Notifications service instance (if not exists)
# 2. Connection from Platform Notification Distribution List to Event Notifications
# 3. Topic in Event Notifications for platform notifications
# 4. Email Destination - IBM built-in email (smtp_ibm) or custom sandbox (smtp_custom_sandbox)
# 5. Email Subscription - Subscribes recipients to receive platform notifications
#
# PLATFORM NOTIFICATION TYPES:
# - Maintenance: Scheduled maintenance events
# - Incident: Unexpected impacting events
# - Security Bulletins: Security vulnerability announcements
# - Announcements: New features and services updates
# - Resource: Resource activity updates
# - Billing and Usage: Billing and usage rate updates
#
# RESULT: Receive IBM Cloud platform notifications via Event Notifications to email
#
# PREREQUISITES:
# 1. Make the script executable:
#    chmod +x en-platform-notifications-src-and-email-dest.sh
#
# 2. Run the script:
#    ./en-platform-notification-src-and-email-dest.sh
#
# 3. Configure variables:
# You can customize the script behavior by setting environment variables before running:
#
#   EN_RESOURCE_GROUP   - IBM Cloud resource group for Event Notifications (default: Default)
#   EN_REGION           - IBM Cloud region for Event Notifications (default: us-south)
#   SERVICE_NAME        - Name of Event Notifications instance (default: platform-notifications-en)
#   PLAN                - Service plan: lite or standard (default: standard)
#   TOPIC_NAME          - Name of the topic for platform notifications (default: Platform Notifications)
#   DESTINATION_NAME    - Name of the destination (default: platform-email-destination)
#   SUBSCRIPTION_NAME   - Name of the subscription (default: platform-email-subscription)
#   DESTINATION_TYPE    - Type of destination: smtp_ibm or smtp_custom_sandbox (default: smtp_ibm)
#                         - smtp_ibm: IBM Event Notifications built-in email (IBM email addresses only, production ready)
#                         - smtp_custom_sandbox: Custom email sandbox (for testing only, not for production)
#   EMAIL_RECIPIENTS    - Comma-separated email addresses for subscription (default: user@example.com)
#                         NOTE: For smtp_ibm, only IBM email addresses (@ibm.com) are supported
#                         NOTE: smtp_custom_sandbox is for testing purposes only, not recommended for production
#
# EXAMPLE USAGE:
#   export EN_RESOURCE_GROUP="production"
#   export EN_REGION="us-south"
#   export SERVICE_NAME="prod-platform-notifications"
#   export EMAIL_RECIPIENTS="admin@ibm.com,ops@ibm.com"
#   export DESTINATION_TYPE="smtp_ibm"
#  
# 4. Run the script: 
#   ./en-platform-notification-src-and-email-dest.sh
#
# ==========================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
EN_RESOURCE_GROUP="${EN_RESOURCE_GROUP:-Default}"
EN_REGION="${EN_REGION:-us-south}"
SERVICE_NAME="${SERVICE_NAME:-my-platform-notifications-en}"
PLAN="${PLAN:-standard}"
SERVICE_ENDPOINTS="${SERVICE_ENDPOINTS:-public-and-private}"
TOPIC_NAME="${TOPIC_NAME:-Platform Notifications}"
DESTINATION_NAME="${DESTINATION_NAME:-platform-email-destination}"
SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-platform-email-subscription}"
DESTINATION_TYPE="${DESTINATION_TYPE:-smtp_ibm}"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-user@example.com}"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if Event Notifications plugin is installed
install_en_plugin() {
    print_message "$YELLOW" "Checking Event Notifications CLI plugin..."
    
    if ibmcloud plugin show event-notifications > /dev/null 2>&1; then
        print_message "$GREEN" "✓ Event Notifications plugin is already installed."
        
        # Check for updates silently
        UPDATE_OUTPUT=$(ibmcloud plugin update event-notifications -f 2>&1)
        if echo "$UPDATE_OUTPUT" | grep -q "No updates are available"; then
            print_message "$GREEN" "✓ Plugin is up to date."
        elif echo "$UPDATE_OUTPUT" | grep -q "was updated successfully"; then
            print_message "$GREEN" "✓ Plugin updated successfully."
        fi
    else
        print_message "$YELLOW" "Installing Event Notifications plugin..."
        ibmcloud plugin install event-notifications -f > /dev/null 2>&1
        print_message "$GREEN" "✓ Event Notifications plugin installed successfully."
    fi
}

# Function to verify IBM Cloud login status
verify_ibmcloud_login() {
    # First check: Try to get IAM token (most reliable check)
    IAM_TOKEN_CHECK=$(ibmcloud iam oauth-tokens 2>&1)
    
    if echo "$IAM_TOKEN_CHECK" | grep -q "not logged in\|FAILED\|No valid authentication token"; then
        print_message "$RED" "✗ Not logged in to IBM Cloud."
        return 1
    fi
    
    # Second check: Verify target information
    TARGET_JSON=$(ibmcloud target --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$TARGET_JSON" ]; then
        print_message "$RED" "✗ Failed to retrieve IBM Cloud target information."
        return 1
    fi
    
    # Extract user information
    USER_EMAIL=$(echo "$TARGET_JSON" | jq -r '.user.user_email // .user.email // .user_email // empty')
    ACCOUNT_NAME=$(echo "$TARGET_JSON" | jq -r '.account.name // .account_name // empty')
    ACCOUNT_ID=$(echo "$TARGET_JSON" | jq -r '.account.guid // .account_id // empty')
    
    # Check if critical information is missing
    if [ -z "$ACCOUNT_ID" ] || [ -z "$ACCOUNT_NAME" ]; then
        print_message "$RED" "✗ Login verification failed - missing account information"
        return 1
    fi
    
    # Third check: Verify IAM token is valid JSON
    IAM_TOKEN=$(ibmcloud iam oauth-tokens --output json 2>/dev/null | jq -r '.iam_token // empty')
    
    if [ -z "$IAM_TOKEN" ]; then
        print_message "$RED" "✗ Failed to retrieve valid IAM token."
        return 1
    fi
    
    # Display concise login information
    print_message "$GREEN" "✓ Logged in as: $USER_EMAIL | Account: $ACCOUNT_NAME"
    
    return 0
}

# Function to login to IBM Cloud
login_ibmcloud() {
    print_message "$YELLOW" "Checking IBM Cloud login status..."
    
    # Use the verification function
    if verify_ibmcloud_login; then
        print_message "$GREEN" "Already logged in to IBM Cloud."
        return 0
    fi
    
    # Not logged in - prompt user for login method
    print_message "$RED" "Not logged in to IBM Cloud."
    echo ""
    print_message "$YELLOW" "Please choose a login method:"
    echo "  1) SSO (Single Sign-On) - Opens browser for authentication"
    echo "  2) API Key - Login using IBM Cloud API key"
    echo "  3) Exit - Cancel and exit script"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-3): " choice
        
        case $choice in
            1)
                print_message "$YELLOW" "Logging in with SSO..."
                if ibmcloud login --sso; then
                    print_message "$GREEN" "✓ Login successful!"
                    # Verify the login
                    if verify_ibmcloud_login; then
                        return 0
                    else
                        print_message "$RED" "Login verification failed. Please try again."
                        exit 1
                    fi
                else
                    print_message "$RED" "Login failed. Please try again."
                    exit 1
                fi
                ;;
            2)
                print_message "$YELLOW" "Logging in with API Key..."
                read -p "Enter your IBM Cloud API Key: " -s apikey
                echo ""
                
                if [ -z "$apikey" ]; then
                    print_message "$RED" "API Key cannot be empty."
                    exit 1
                fi
                
                if ibmcloud login --apikey "$apikey"; then
                    print_message "$GREEN" "✓ Login successful!"
                    # Verify the login
                    if verify_ibmcloud_login; then
                        return 0
                    else
                        print_message "$RED" "Login verification failed. Please try again."
                        exit 1
                    fi
                else
                    print_message "$RED" "Login failed. Please check your API key and try again."
                    exit 1
                fi
                ;;
            3)
                print_message "$YELLOW" "Exiting script..."
                exit 0
                ;;
            *)
                print_message "$RED" "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# Function to get or create Event Notifications instance
get_or_create_en_instance() {
    # Target the resource group and region silently
    ibmcloud target -g "$EN_RESOURCE_GROUP" -r "$EN_REGION" > /dev/null 2>&1
    
    # Check if instance exists
    INSTANCE_CREATED=false
    if ibmcloud resource service-instance "$SERVICE_NAME" > /dev/null 2>&1; then
        print_message "$GREEN" "✓ Using existing Event Notifications instance: $SERVICE_NAME (region: $EN_REGION)"
    else
        print_message "$YELLOW" "Creating Event Notifications instance: $SERVICE_NAME (region: $EN_REGION, plan: $PLAN)..."
        ibmcloud resource service-instance-create "$SERVICE_NAME" event-notifications "$PLAN" "$EN_REGION" \
            -p "{\"service-endpoints\":\"$SERVICE_ENDPOINTS\"}" > /dev/null 2>&1
        
        print_message "$GREEN" "✓ Instance created successfully"
        INSTANCE_CREATED=true
    fi
    
    # Get instance CRN and GUID
    EN_CRN=$(ibmcloud resource service-instance "$SERVICE_NAME" --output json | jq -r '.[0].id')
    EN_GUID=$(ibmcloud resource service-instance "$SERVICE_NAME" --output json | jq -r '.[0].guid')
    
    # Verify the instance details
    if [ -z "$EN_GUID" ] || [ "$EN_GUID" = "null" ]; then
        print_message "$RED" "❌ Failed to retrieve Event Notifications instance GUID"
        print_message "$RED" "Please verify the instance exists: ibmcloud resource service-instance $SERVICE_NAME"
        exit 1
    fi
    
    print_message "$GREEN" "✓ Event Notifications Instance GUID: $EN_GUID"
    print_message "$GREEN" "✓ Event Notifications Instance CRN: $EN_CRN"
    
    # Only verify accessibility and wait if instance was just created
    if [ "$INSTANCE_CREATED" = true ]; then
        print_message "$YELLOW" "Verifying instance accessibility..."
        if ibmcloud event-notifications instance --instance-id "$EN_GUID" > /dev/null 2>&1; then
            print_message "$GREEN" "✓ Instance is accessible via Event Notifications CLI"
        else
            print_message "$YELLOW" "⚠️  Instance may not be fully provisioned yet"
            print_message "$YELLOW" "Waiting 30 seconds for instance to be ready..."
            sleep 30
        fi
    fi
    
    export EN_CRN
    export EN_GUID
}

# Function to add Event Notifications to platform notification distribution list
add_en_to_notification_list() {
    print_message "$YELLOW" "Registering Event Notifications instance with platform notification system..."
    print_message "$YELLOW" "Instance: $SERVICE_NAME (GUID: $EN_GUID)"
    
    # Get IAM token (Bearer format)
    IAM_TOKEN=$(ibmcloud iam oauth-tokens --output json | jq -r '.iam_token')
    
    # Get account ID
    ACCOUNT_ID=$(ibmcloud target --output json | jq -r '.account.guid')
    
    print_message "$YELLOW" "Account ID: $ACCOUNT_ID"
    print_message "$YELLOW" "Event Notifications GUID: $EN_GUID"
    
    # Base URL for Platform Notifications API
    BASE_URL="https://notifications.cloud.ibm.com/api"
    
    # Step 1: Check existing destinations and compare with EN GUID
    print_message "$YELLOW" "Checking if Event Notifications instance is already in the distribution list..."
    print_message "$YELLOW" "Comparing destination_id with EN GUID: $EN_GUID"
    
    GET_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
        "${BASE_URL}/v1/distribution_lists/${ACCOUNT_ID}/destinations" \
        -H "Authorization: ${IAM_TOKEN}" \
        -H "Accept: application/json")
    
    GET_HTTP_CODE=$(echo "$GET_RESPONSE" | tail -n1)
    GET_RESPONSE_BODY=$(echo "$GET_RESPONSE" | sed '$d')
    
    print_message "$YELLOW" "GET Destinations HTTP Status: $GET_HTTP_CODE"
    
    if [ "$GET_HTTP_CODE" = "200" ]; then
        print_message "$GREEN" "✓ Successfully retrieved existing destinations from distribution list"
        
        if echo "$GET_RESPONSE_BODY" | jq empty 2>/dev/null; then
            # Extract all destination IDs for comparison
            DEST_IDS=$(echo "$GET_RESPONSE_BODY" | jq -r '.destinations[]?.destination_id // empty')
            
            if [ -z "$DEST_IDS" ]; then
                print_message "$YELLOW" "No destinations found in the distribution list"
            else
                DEST_COUNT=$(echo "$DEST_IDS" | wc -l | xargs)
                print_message "$YELLOW" "Found $DEST_COUNT existing destination(s) in distribution list"
            fi
            
            # Check if our EN GUID matches any destination_id in the list
            EXISTING_DEST=$(echo "$GET_RESPONSE_BODY" | jq -r ".destinations[]? | select(.destination_id==\"$EN_GUID\") | .destination_id")
            
            if [ -n "$EXISTING_DEST" ] && [ "$EXISTING_DEST" != "null" ]; then
                print_message "$GREEN" "✓✓✓ Event Notifications instance (GUID: $EN_GUID) is ALREADY registered in the distribution list"
                print_message "$GREEN" "Skipping registration - destination already exists"
                return 0
            else
                print_message "$YELLOW" "Event Notifications instance (GUID: $EN_GUID) NOT found in distribution list"
                print_message "$YELLOW" "Will proceed with registration..."
            fi
        fi
    else
        print_message "$YELLOW" "Could not retrieve existing destinations (HTTP $GET_HTTP_CODE)"
        if [ -n "$GET_RESPONSE_BODY" ]; then
            print_message "$YELLOW" "Response:"
            echo "$GET_RESPONSE_BODY"
        fi
        print_message "$YELLOW" "Will attempt to register anyway..."
    fi
    
    # Step 2: Register Event Notifications instance as a destination
    print_message "$YELLOW" "Registering Event Notifications as platform notification destination..."
    print_message "$YELLOW" "Destination ID: $EN_GUID"
    
    # Create the request body according to API spec
    REQUEST_BODY=$(jq -n \
        --arg dest_id "$EN_GUID" \
        --arg dest_type "event_notifications" \
        '{
            destination_id: $dest_id,
            destination_type: $dest_type
        }')
    
    REGISTER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "${BASE_URL}/v1/distribution_lists/${ACCOUNT_ID}/destinations" \
        -H "Authorization: ${IAM_TOKEN}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_BODY")
    
    # Extract HTTP status code and response body
    HTTP_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$REGISTER_RESPONSE" | sed '$d')
    
    # Check if registration was successful
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        print_message "$GREEN" "✓ Successfully registered with platform notification system"
    elif [ "$HTTP_CODE" = "409" ]; then
        print_message "$GREEN" "✓ Already registered"
    else
        print_message "$YELLOW" "⚠️  Could not register via API (HTTP $HTTP_CODE)"
        print_message "$YELLOW" "Manual setup required: Manage > Account > Notification distribution list"
    fi
}

# Function to set Event Notifications endpoint based on region
set_en_endpoint() {
    local region=$1
    
    case "$region" in
        us-south)
            export IBMCLOUD_EN_ENDPOINT="https://us-south.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        eu-gb)
            export IBMCLOUD_EN_ENDPOINT="https://eu-gb.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        au-syd)
            export IBMCLOUD_EN_ENDPOINT="https://au-syd.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        eu-de)
            export IBMCLOUD_EN_ENDPOINT="https://eu-de.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        eu-es)
            export IBMCLOUD_EN_ENDPOINT="https://eu-es.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        jp-osa)
            export IBMCLOUD_EN_ENDPOINT="https://jp-osa.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        jp-tok)
            export IBMCLOUD_EN_ENDPOINT="https://jp-tok.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        ca-tor)
            export IBMCLOUD_EN_ENDPOINT="https://ca-tor.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        br-sao)
            export IBMCLOUD_EN_ENDPOINT="https://br-sao.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        ca-mon)
            export IBMCLOUD_EN_ENDPOINT="https://ca-mon.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        us-east)
            export IBMCLOUD_EN_ENDPOINT="https://us-east.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        in-che)
            export IBMCLOUD_EN_ENDPOINT="https://in-che.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        in-mum)
            export IBMCLOUD_EN_ENDPOINT="https://in-mum.event-notifications.cloud.ibm.com/event-notifications"
            ;;
        *)
            print_message "$YELLOW" "⚠️  Unknown region: $region, using default endpoint (us-south)"
            export IBMCLOUD_EN_ENDPOINT="https://us-south.event-notifications.cloud.ibm.com/event-notifications"
            ;;
    esac
    
    print_message "$GREEN" "✓ Event Notifications endpoint set to: $IBMCLOUD_EN_ENDPOINT"
}

# Function to initialize Event Notifications CLI
init_en_cli() {
    # Set the EN endpoint for the region
    set_en_endpoint "$EN_REGION"
    
    # Ensure we're in the correct region
    ibmcloud target -r "$EN_REGION" > /dev/null 2>&1
    
    # Initialize the EN CLI with the instance
    if ibmcloud event-notifications init --instance-id "$EN_GUID" > /dev/null 2>&1; then
        print_message "$GREEN" "✓ Event Notifications CLI initialized"
    else
        print_message "$YELLOW" "⚠️  CLI init failed, will use --instance-id flag"
    fi
}

# Function to create a topic for platform notifications
create_platform_topic() {
    print_message "$YELLOW" "Setting up topic: $TOPIC_NAME"
    
    # Check if topic already exists
    TOPICS_TEST=$(ibmcloud event-notifications topics --instance-id "$EN_GUID" --output json 2>&1)
    
    if echo "$TOPICS_TEST" | jq empty 2>/dev/null; then
        EXISTING_TOPIC=$(echo "$TOPICS_TEST" | jq -r ".topics[]? | select(.name==\"$TOPIC_NAME\") | .id")
        
        if [ -n "$EXISTING_TOPIC" ] && [ "$EXISTING_TOPIC" != "null" ]; then
            print_message "$GREEN" "✓ Using existing topic"
            TOPIC_ID="$EXISTING_TOPIC"
        else
            TOPIC_RESPONSE=$(ibmcloud event-notifications topic-create \
                --instance-id "$EN_GUID" \
                --name "$TOPIC_NAME" \
                --description "Topic for IBM Cloud platform notifications" \
                --output json 2>&1)
            
            if echo "$TOPIC_RESPONSE" | jq empty 2>/dev/null; then
                TOPIC_ID=$(echo "$TOPIC_RESPONSE" | jq -r '.id')
                print_message "$GREEN" "✓ Topic created"
            else
                print_message "$RED" "✗ Failed to create topic"
                exit 1
            fi
        fi
    else
        print_message "$RED" "✗ Failed to connect to Event Notifications instance"
        exit 1
    fi
    
    export TOPIC_ID
}

# Function to connect platform notification source to topic
connect_platform_source_to_topic() {
    # Get the platform notification source ID
    SOURCES_JSON=$(ibmcloud event-notifications sources --instance-id "$EN_GUID" --output json)
    SOURCE_ID=$(echo "$SOURCES_JSON" | jq -r '.sources[] | select(.name | contains("Platform") or contains("Notification")) | .id' | head -1)
    
    if [ -n "$SOURCE_ID" ] && [ "$SOURCE_ID" != "null" ]; then
        ibmcloud event-notifications topic-replace \
            --instance-id "$EN_GUID" \
            --id "$TOPIC_ID" \
            --name "$TOPIC_NAME" \
            --description "Topic connected to platform notification source" \
            --sources "[{\"id\":\"$SOURCE_ID\",\"rules\":[{\"enabled\":true,\"event_type_filter\":\"$.*\"}]}]" \
            --output json > /dev/null
        
        print_message "$GREEN" "✓ Connected to platform notification source (all event types)"
    fi
}

# Function to create email destination
create_destination() {
    if [ "$DESTINATION_TYPE" == "smtp_ibm" ]; then
        DESTINATIONS_JSON=$(ibmcloud event-notifications destinations --instance-id "$EN_GUID" --output json)
        DESTINATION_ID=$(echo "$DESTINATIONS_JSON" | jq -r '.destinations[] | select(.type=="smtp_ibm") | .id' | head -1)
        
        if [ -n "$DESTINATION_ID" ] && [ "$DESTINATION_ID" != "null" ]; then
            print_message "$GREEN" "✓ Using IBM built-in email destination"
        else
            DESTINATION_RESPONSE=$(ibmcloud event-notifications destination-create \
                --instance-id "$EN_GUID" \
                --name "$DESTINATION_NAME" \
                --type "$DESTINATION_TYPE" \
                --description "IBM Event Notifications built-in email" \
                --output json)
            
            DESTINATION_ID=$(echo "$DESTINATION_RESPONSE" | jq -r '.id')
            print_message "$GREEN" "✓ Email destination created"
        fi
    else
        if ibmcloud event-notifications destinations --instance-id "$EN_GUID" 2>/dev/null | grep -q "$DESTINATION_NAME"; then
            DESTINATION_ID=$(ibmcloud event-notifications destinations --instance-id "$EN_GUID" --output json | jq -r ".destinations[] | select(.name==\"$DESTINATION_NAME\") | .id")
            print_message "$GREEN" "✓ Using existing custom email destination"
        else
            DESTINATION_RESPONSE=$(ibmcloud event-notifications destination-create \
                --instance-id "$EN_GUID" \
                --name "$DESTINATION_NAME" \
                --type "$DESTINATION_TYPE" \
                --description "Custom email sandbox (testing only)" \
                --output json)
            
            DESTINATION_ID=$(echo "$DESTINATION_RESPONSE" | jq -r '.id')
            print_message "$GREEN" "✓ Custom email destination created"
            print_message "$YELLOW" "⚠️ Custom email sandbox is for testing only, not for production"
        fi
    fi
    
    export DESTINATION_ID
}

# Function to create email subscription
create_subscription() {
    # Validate email addresses for smtp_ibm destination type
    if [ "$DESTINATION_TYPE" == "smtp_ibm" ]; then
        IFS=',' read -ra EMAIL_ARRAY <<< "$EMAIL_RECIPIENTS"
        NON_IBM_EMAILS=()
        
        for email in "${EMAIL_ARRAY[@]}"; do
            email=$(echo "$email" | xargs) # trim whitespace
            if [[ ! "$email" =~ @ibm\.com$ ]]; then
                NON_IBM_EMAILS+=("$email")
            fi
        done
        
        if [ ${#NON_IBM_EMAILS[@]} -gt 0 ]; then
            print_message "$RED" "⚠️  WARNING: smtp_ibm only supports @ibm.com addresses"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    # Check if subscription already exists
    SUBSCRIPTIONS_JSON=$(ibmcloud event-notifications subscriptions --instance-id "$EN_GUID" --output json 2>/dev/null)
    EXISTING_SUBSCRIPTION=$(echo "$SUBSCRIPTIONS_JSON" | jq -r ".subscriptions[]? | select(.name==\"$SUBSCRIPTION_NAME\")")
    
    if [ -n "$EXISTING_SUBSCRIPTION" ] && [ "$EXISTING_SUBSCRIPTION" != "null" ]; then
        SUBSCRIPTION_ID=$(echo "$EXISTING_SUBSCRIPTION" | jq -r '.id')
        
        # Get existing invited emails
        EXISTING_EMAILS=$(echo "$EXISTING_SUBSCRIPTION" | jq -r '.attributes.invited[]?' 2>/dev/null || echo "")
        
        # Convert requested emails to array (trim whitespace)
        IFS=',' read -ra REQUESTED_EMAIL_ARRAY <<< "$EMAIL_RECIPIENTS"
        NEW_EMAILS=()
        for email in "${REQUESTED_EMAIL_ARRAY[@]}"; do
            trimmed=$(echo "$email" | xargs)
            # Check if email is not in existing list
            if ! echo "$EXISTING_EMAILS" | grep -qx "$trimmed"; then
                NEW_EMAILS+=("$trimmed")
            fi
        done
        
        if [ ${#NEW_EMAILS[@]} -gt 0 ]; then
            print_message "$YELLOW" "Adding ${#NEW_EMAILS[@]} new email(s) to subscription..."
            
            # Create JSON array of new emails to add
            NEW_EMAILS_JSON=$(printf '%s\n' "${NEW_EMAILS[@]}" | jq -R . | jq -s .)
            
            # Build attributes based on destination type
            if [ "$DESTINATION_TYPE" == "smtp_ibm" ]; then
                ATTRIBUTES_JSON="{\"invited\":{\"add\":$NEW_EMAILS_JSON},\"add_notification_payload\":true,\"reply_to_mail\":\"no-reply@cloud.ibm.com\",\"reply_to_name\":\"IBM Cloud Notifications\",\"from_name\":\"IBM Cloud Platform\"}"
            else
                # For custom email sandbox, include template fields
                ATTRIBUTES_JSON="{\"invited\":{\"add\":$NEW_EMAILS_JSON},\"add_notification_payload\":true,\"reply_to_mail\":\"no-reply@cloud.ibm.com\",\"reply_to_name\":\"IBM Cloud Notifications\"}"
            fi
            
            # Update subscription with add/remove format
            UPDATE_RESPONSE=$(ibmcloud event-notifications subscription-update \
                --instance-id "$EN_GUID" \
                --id "$SUBSCRIPTION_ID" \
                --attributes "$ATTRIBUTES_JSON" \
                --output json 2>&1)
            
            if [ $? -eq 0 ]; then
                print_message "$GREEN" "✓ Subscription updated with new emails"
            else
                print_message "$YELLOW" "⚠️  Could not update subscription"
                print_message "$YELLOW" "  Error: $UPDATE_RESPONSE"
            fi
        else
            print_message "$GREEN" "✓ Using existing subscription (all emails already added)"
        fi
    else
        # Convert comma-separated emails to JSON array format
        IFS=',' read -ra EMAIL_ARRAY <<< "$EMAIL_RECIPIENTS"
        TRIMMED_EMAILS=()
        for email in "${EMAIL_ARRAY[@]}"; do
            TRIMMED_EMAILS+=("$(echo "$email" | xargs)")
        done
        EMAIL_JSON=$(printf '%s\n' "${TRIMMED_EMAILS[@]}" | jq -R . | jq -s .)
        
        SUBSCRIPTION_RESPONSE=$(ibmcloud event-notifications subscription-create \
            --instance-id "$EN_GUID" \
            --name "$SUBSCRIPTION_NAME" \
            --description "Email subscription for IBM Cloud platform notifications" \
            --destination-id "$DESTINATION_ID" \
            --topic-id "$TOPIC_ID" \
            --attributes "{\"invited\":$EMAIL_JSON,\"add_notification_payload\":true,\"reply_to_mail\":\"no-reply@cloud.ibm.com\",\"reply_to_name\":\"IBM Cloud Notifications\",\"from_name\":\"IBM Cloud Platform\"}" \
            --output json)
        
        SUBSCRIPTION_ID=$(echo "$SUBSCRIPTION_RESPONSE" | jq -r '.id')
        print_message "$GREEN" "✓ Subscription created for: $EMAIL_RECIPIENTS"
    fi
    
    export SUBSCRIPTION_ID
}

# Function to display summary
display_summary() {
    print_message "$GREEN" "\n=========================================="
    print_message "$GREEN" "Platform Notifications Setup Complete!"
    print_message "$GREEN" "=========================================="
    echo ""
    print_message "$YELLOW" "Event Notifications Instance:"
    echo "  Service Name: $SERVICE_NAME"
    echo "  CRN: $EN_CRN"
    echo "  GUID: $EN_GUID"
    echo ""
    print_message "$YELLOW" "Created Resources:"
    echo "  Topic ID: $TOPIC_ID (Platform Notifications)"
    
    if [ "$DESTINATION_TYPE" == "smtp_ibm" ]; then
        echo "  Destination ID: $DESTINATION_ID (IBM Event Notifications Built-in Email)"
    else
        echo "  Destination ID: $DESTINATION_ID (Custom Email Sandbox)"
    fi
    
    echo "  Subscription ID: $SUBSCRIPTION_ID"
    echo ""
    print_message "$YELLOW" "Notification Configuration:"
    echo "  ✓ Wildcard rule enabled - ALL platform notification types will be received"
    echo "  ✓ This includes: Maintenance, Incidents, Security Bulletins, Announcements, Resource updates, and Billing/Usage notifications"
    echo "  ℹ️  To filter specific event types, edit the Event Notifications topic rules in the IBM Cloud Console"
    echo ""
    print_message "$YELLOW" "Email Recipients:"
    echo "  $EMAIL_RECIPIENTS"
    echo ""
    print_message "$YELLOW" "⚠️  IMPORTANT: Email Subscription Confirmation Required"
    print_message "$YELLOW" "Email invites have been sent to: $EMAIL_RECIPIENTS"
    print_message "$YELLOW" "Each recipient must:"
    print_message "$YELLOW" "  1. Check their email inbox"
    print_message "$YELLOW" "  2. Click the confirmation link in the email"
    print_message "$YELLOW" "  3. Confirm the subscription"
    print_message "$YELLOW" "Platform notifications will only be sent to confirmed email addresses."
    echo ""
    print_message "$GREEN" "=========================================="
    print_message "$GREEN" "You will now receive IBM Cloud platform notifications via email!"
    print_message "$GREEN" "=========================================="
}

# Main execution
main() {
    print_message "$GREEN" "Starting IBM Cloud Platform Notifications setup..."
    echo ""
    
    # Install prerequisites
    install_en_plugin
    
    # Login and setup
    login_ibmcloud
    
    # Get or create Event Notifications instance
    get_or_create_en_instance
    
    # Add Event Notifications to platform notification distribution list
    add_en_to_notification_list
    
    # Initialize Event Notifications CLI
    init_en_cli
    
    # Create topic for platform notifications
    create_platform_topic
    
    # Connect platform notification source to topic
    connect_platform_source_to_topic
    
    # Create email destination
    create_destination
    
    # Create email subscription
    create_subscription
    
    # Display summary
    display_summary
    
    print_message "$GREEN" "\nScript completed successfully!"
}

# Run main function
main

