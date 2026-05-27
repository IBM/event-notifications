#!/bin/bash

# =================================================
# IBM Cloud Event Notifications Provisioning Script
# =================================================
# This script automates the complete setup of IBM Cloud Event Notifications with IBM Cloud Logs integration.
#
# WHAT THIS SCRIPT CREATES:
# 1. Event Notifications service instance (if not exists)
# 2. IAM Authorization Policy - Grants IBM Cloud Logs access to Event Notifications
# 3. Outbound Integration - Connects IBM Cloud Logs to Event Notifications (auto-creates source)
# 4. Alert in IBM Cloud Logs - Sample alert which triggers events for all logs
# 5. Topic in Event Notifications - Routes events from the source
# 6. Source-to-Topic Connection - Links IBM Cloud Logs source to the topic (wildcard rule)
# 7. Email Destination - IBM built-in email (smtp_ibm) or custom sandbox (smtp_custom_sandbox)
# 8. Email Subscription - Subscribes recipients to receive notifications from the topic
#
# RESULT: A complete notification pipeline from IBM Cloud Logs alerts to email recipients
#
# PREREQUISITES:
# 1. Make the script executable:
#    chmod +x en-icl-src-and-email-dest.sh
#
# 2. Account Requirements:
#    - By default, this script creates a LITE plan instance (free tier)
#    - RECOMMENDED: Use STANDARD plan for production workloads (requires Pay-As-You-Go account)
#    - To use STANDARD plan, set PLAN variable to "standard"
#    - Note: LITE plan has limited features and is suitable for testing only
#
# 3. Configure variables:
# You can customize the script behavior by setting environment variables before running:
#
#   EN_RESOURCE_GROUP   - IBM Cloud resource group for Event Notifications (default: Default)
#   EN_REGION           - IBM Cloud region for Event Notifications (default: us-south)
#   SERVICE_NAME        - Name of Event Notifications instance (default: my-event-notifications)
#   PLAN                - Service plan: lite or standard (default: lite, RECOMMENDED: standard for production)
#   SERVICE_ENDPOINTS   - Endpoint type: public, private, or public-and-private (default: public-and-private)
#   ICL_CRN             - CRN of IBM Cloud Logs instance (required)
#   ICL_RESOURCE_GROUP  - Resource group of IBM Cloud Logs instance (default: Default)
#   ICL_REGION          - IBM Cloud region for IBM Cloud Logs (default: us-south)
#   TOPIC_NAME          - Name of the topic (default: my-topic)
#   SOURCE_NAME         - Name of the IBM Cloud Logs source (default: IBM Cloud Logs Source)
#   DESTINATION_NAME    - Name of the destination (default: my-destination)
#   SUBSCRIPTION_NAME   - Name of the subscription (default: my-subscription)
#   DESTINATION_TYPE    - Type of destination: smtp_ibm or smtp_custom_sandbox (default: smtp_ibm)
#                         - smtp_ibm: IBM Event Notifications built-in email (IBM email addresses only, production ready)
#                         - smtp_custom_sandbox: Custom email sandbox (for testing only, not for production)
#   EMAIL_RECIPIENTS    - Comma-separated email addresses for subscription (default: user@example.com)
#                         NOTE: For smtp_ibm, only IBM email addresses (@ibm.com) are supported
#                         NOTE: smtp_custom_sandbox is for testing purposes only, not recommended for production
#   ALERT_NAME          - Name of the IBM Cloud Logs alert (default: Event Notifications Alert)
#   ALERT_SEVERITY      - Alert severity: info_or_unspecified, warning, critical, error (default: info_or_unspecified)
#   ALERT_QUERY         - Query/filter for the alert (default: empty - matches all logs)
#                         Examples:
#                         - "error" (matches logs containing "error")
#                         - "status:500" (matches logs with status 500)
#                         - "application:myapp AND level:error" (complex query)
#
# EXAMPLE USAGE WITH CUSTOM VARIABLES:
#   # Using custom email sandbox (no verification needed):
#   export EN_RESOURCE_GROUP="production"
#   export EN_REGION="us-south"
#   export SERVICE_NAME="prod-event-notifications"
#   export PLAN="standard"
#   export ICL_CRN="crn:v1:bluemix:public:logs:eu-gb:a/..."
#   export ICL_RESOURCE_GROUP="production"
#   export ICL_REGION="eu-gb"
#   export EMAIL_RECIPIENTS="user@example.com,admin@example.com"
#   export ALERT_QUERY="level:error OR level:critical"
#   export DESTINATION_TYPE="smtp_custom_sandbox"
#
# 4. Run the script:
#   ./en-icl-src-and-email-dest.sh
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
SERVICE_NAME="${SERVICE_NAME:-my-event-notifications}"
PLAN="${PLAN:-standard}"
SERVICE_ENDPOINTS="${SERVICE_ENDPOINTS:-public-and-private}"
ICL_CRN="${ICL_CRN:-}"
ICL_RESOURCE_GROUP="${ICL_RESOURCE_GROUP:-Default}"
ICL_REGION="${ICL_REGION:-us-south}"
TOPIC_NAME="${TOPIC_NAME:-my-topic}"
SOURCE_NAME="${SOURCE_NAME:-IBM Cloud Logs Source}"
DESTINATION_NAME="${DESTINATION_NAME:-my-destination}"
SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-my-subscription}"
DESTINATION_TYPE="${DESTINATION_TYPE:-smtp_ibm}"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-user@example.com}"
ALERT_NAME="${ALERT_NAME:-Event Notifications Alert}"
ALERT_SEVERITY="${ALERT_SEVERITY:-info_or_unspecified}"
ALERT_QUERY="${ALERT_QUERY:-}"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install IBM Cloud CLI
install_ibmcloud_cli() {
    print_message "$YELLOW" "Checking IBM Cloud CLI installation..."
    
    if command_exists ibmcloud; then
        print_message "$GREEN" "IBM Cloud CLI is already installed."
        ibmcloud --version
        
        # Check for CLI updates
        print_message "$YELLOW" "Checking for IBM Cloud CLI updates..."
        ibmcloud update -f 2>/dev/null || print_message "$YELLOW" "CLI update check completed."
    else
        print_message "$YELLOW" "Installing IBM Cloud CLI..."
        curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
        print_message "$GREEN" "IBM Cloud CLI installed successfully."
    fi
}

# Function to install Event Notifications CLI plugin
install_en_plugin() {
    print_message "$YELLOW" "Checking Event Notifications CLI plugin..."
    
    if ibmcloud plugin list | grep -q "event-notifications"; then
        print_message "$GREEN" "Event Notifications plugin is already installed."
        # Suppress detailed plugin output
        ibmcloud plugin show event-notifications > /dev/null 2>&1
        
        # Check for updates
        print_message "$YELLOW" "Checking for plugin updates..."
        ibmcloud plugin update event-notifications -f
    else
        print_message "$YELLOW" "Installing Event Notifications CLI plugin..."
        ibmcloud plugin install event-notifications -f
        print_message "$GREEN" "Event Notifications plugin installed successfully."
    fi
}

# Function to install IBM Cloud Logs CLI plugin
install_logs_plugin() {
    print_message "$YELLOW" "Checking IBM Cloud Logs CLI plugin..."
    
    if ibmcloud plugin list | grep -q "cloud-logs"; then
        print_message "$GREEN" "IBM Cloud Logs plugin is already installed."
        # Suppress detailed plugin output
        ibmcloud plugin show cloud-logs > /dev/null 2>&1
        
        # Check for updates
        print_message "$YELLOW" "Checking for plugin updates..."
        ibmcloud plugin update cloud-logs -f
    else
        print_message "$YELLOW" "Installing IBM Cloud Logs CLI plugin..."
        ibmcloud plugin install cloud-logs -f
        print_message "$GREEN" "IBM Cloud Logs plugin installed successfully."
    fi
}

# Function to verify IBM Cloud login status
verify_ibmcloud_login() {
    print_message "$YELLOW" "Verifying IBM Cloud login status..."
    
    # First check: Try to get IAM token (most reliable check)
    IAM_TOKEN_CHECK=$(ibmcloud iam oauth-tokens 2>&1)
    
    if echo "$IAM_TOKEN_CHECK" | grep -q "not logged in\|FAILED\|No valid authentication token"; then
        print_message "$RED" "✗ Not logged in to IBM Cloud."
        print_message "$YELLOW" "Please login using: ibmcloud login --sso"
        return 1
    fi
    
    # Second check: Verify target information
    TARGET_JSON=$(ibmcloud target --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$TARGET_JSON" ]; then
        print_message "$RED" "✗ Failed to retrieve IBM Cloud target information."
        print_message "$YELLOW" "Please login using: ibmcloud login --sso"
        return 1
    fi
    
    # Extract user information
    USER_EMAIL=$(echo "$TARGET_JSON" | jq -r '.user.user_email // .user.email // .user_email // empty')
    ACCOUNT_NAME=$(echo "$TARGET_JSON" | jq -r '.account.name // .account_name // empty')
    ACCOUNT_ID=$(echo "$TARGET_JSON" | jq -r '.account.guid // .account_id // empty')
    CURRENT_REGION=$(echo "$TARGET_JSON" | jq -r '.region.name // .region // empty')
    CURRENT_RG=$(echo "$TARGET_JSON" | jq -r '.resource_group.name // .resource_group // empty')
    
    # Check if critical information is missing
    if [ -z "$ACCOUNT_ID" ] || [ -z "$ACCOUNT_NAME" ]; then
        print_message "$RED" "✗ Login verification failed - missing account information"
        print_message "$RED" "  User: ${USER_EMAIL:-Unknown}"
        print_message "$RED" "  Account: ${ACCOUNT_NAME:-Unknown}"
        print_message "$RED" "  Account ID: ${ACCOUNT_ID:-Unknown}"
        print_message "$YELLOW" "You may not be properly logged in. Please run: ibmcloud login --sso"
        return 1
    fi
    
    # Third check: Verify IAM token is valid JSON
    print_message "$YELLOW" "Verifying IAM token validity..."
    IAM_TOKEN=$(ibmcloud iam oauth-tokens --output json 2>/dev/null | jq -r '.iam_token // empty')
    
    if [ -z "$IAM_TOKEN" ]; then
        print_message "$RED" "✗ Failed to retrieve valid IAM token."
        print_message "$YELLOW" "Your session may have expired. Please login again: ibmcloud login --sso"
        return 1
    fi
    
    # Display login information only if all checks passed
    print_message "$GREEN" "✓ Successfully logged in to IBM Cloud"
    echo "  User: ${USER_EMAIL:-Unknown}"
    echo "  Account: $ACCOUNT_NAME"
    echo "  Account ID: $ACCOUNT_ID"
    echo "  Current Region: ${CURRENT_REGION:-Not set}"
    echo "  Current Resource Group: ${CURRENT_RG:-Not set}"
    print_message "$GREEN" "✓ IAM token is valid"
    
    return 0
}

# Function to login to IBM Cloud
login_ibmcloud() {
    print_message "$YELLOW" "Checking IBM Cloud login status..."
    
    # Use the verification function
    if verify_ibmcloud_login; then
        print_message "$GREEN" "Already logged in to IBM Cloud."
    else
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
                            break
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
                            break
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
    fi
    
    # Set target resource group and region for Event Notifications
    print_message "$YELLOW" "Setting target resource group: $EN_RESOURCE_GROUP and region: $EN_REGION"
    ibmcloud target -g "$EN_RESOURCE_GROUP" -r "$EN_REGION"
}

# Function to provision Event Notifications instance
provision_en_instance() {
    if ibmcloud resource service-instance "$SERVICE_NAME" >/dev/null 2>&1; then
        print_message "$GREEN" "✓ Using existing Event Notifications instance: $SERVICE_NAME (region: $EN_REGION)"
    else
        print_message "$YELLOW" "Creating Event Notifications instance: $SERVICE_NAME (region: $EN_REGION, plan: $PLAN)..."
        
        # Create the instance with service endpoints parameter
        if [ "$PLAN" == "lite" ]; then
            # Lite plan may not support service endpoints parameter
            ibmcloud resource service-instance-create "$SERVICE_NAME" \
                event-notifications "$PLAN" "$EN_REGION" \
                -g "$EN_RESOURCE_GROUP"
        else
            # Standard plan with service endpoints
            ibmcloud resource service-instance-create "$SERVICE_NAME" \
                event-notifications "$PLAN" "$EN_REGION" \
                -g "$EN_RESOURCE_GROUP" \
                --service-endpoints "$SERVICE_ENDPOINTS"
        fi
        
        print_message "$GREEN" "✓ Instance created successfully"
        
        # Mark that instance was just created
        INSTANCE_JUST_CREATED=true
    fi
}

# Function to get CRN of Event Notifications instance
get_en_crn() {
    print_message "$YELLOW" "Retrieving CRN and GUID of Event Notifications instance..."
    
    EN_CRN=$(ibmcloud resource service-instance "$SERVICE_NAME" --output json | jq -r '.[0].crn')
    
    if [ -z "$EN_CRN" ] || [ "$EN_CRN" == "null" ]; then
        print_message "$RED" "Failed to retrieve CRN for Event Notifications instance."
        exit 1
    fi
    
    # Extract GUID from CRN (format: crn:v1:...:guid::)
    EN_GUID=$(ibmcloud resource service-instance "$SERVICE_NAME" --output json | jq -r '.[0].guid')
    
    if [ -z "$EN_GUID" ] || [ "$EN_GUID" == "null" ]; then
        print_message "$RED" "Failed to retrieve GUID for Event Notifications instance."
        exit 1
    fi
    
    print_message "$GREEN" "Event Notifications CRN: $EN_CRN"
    print_message "$GREEN" "Event Notifications GUID: $EN_GUID"
    export EN_CRN
    export EN_GUID
}

# Function to wait for instance to be ready
wait_for_instance_ready() {
    if [ "$INSTANCE_JUST_CREATED" = true ]; then
        print_message "$YELLOW" "Waiting for newly created instance to be fully ready..."
        print_message "$YELLOW" "This may take 2-3 minutes..."
        
        local max_attempts=5
        local attempt=0
        local wait_time=5
        
        while [ $attempt -lt $max_attempts ]; do
            attempt=$((attempt + 1))
            print_message "$YELLOW" "Checking instance status (attempt $attempt/$max_attempts)..."
            
            # Check if instance state is active
            local state=$(ibmcloud resource service-instance "$SERVICE_NAME" --output json | jq -r '.[0].state')
            
            if [ "$state" == "active" ]; then
                # Additional wait to ensure API is ready
                print_message "$YELLOW" "Instance is active. Waiting additional 30 seconds for API readiness..."
                sleep 30
                print_message "$GREEN" "Instance is ready!"
                return 0
            fi
            
            sleep $wait_time
        done
        
        print_message "$RED" "Instance did not become ready in time. Please check IBM Cloud console."
        exit 1
    else
        print_message "$GREEN" "Using existing instance (already ready)."
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
    print_message "$YELLOW" "Initializing Event Notifications CLI with instance..."
    
    # Set the EN endpoint for the region
    set_en_endpoint "$EN_REGION"
    
    ibmcloud event-notifications init --instance-id "$EN_GUID"
    print_message "$GREEN" "Event Notifications CLI initialized successfully."
}

# Function to validate IBM Cloud Logs instance CRN and extract instance ID
validate_icl_crn() {
    if [ -z "$ICL_CRN" ]; then
        print_message "$RED" "ICL_CRN is required. Please set it before running the script."
        print_message "$YELLOW" "Example: export ICL_CRN='crn:v1:bluemix:public:logs:us-south:a/...'"
        print_message "$YELLOW" "You can get the CRN from your IBM Cloud Logs instance details"
        exit 1
    fi
    
    # Extract instance ID from ICL CRN
    # CRN format: crn:v1:bluemix:public:logs:REGION:a/ACCOUNT:INSTANCE_ID::
    ICL_INSTANCE_ID=$(echo "$ICL_CRN" | awk -F: '{print $8}')
    
    if [ -z "$ICL_INSTANCE_ID" ]; then
        print_message "$RED" "Failed to extract instance ID from ICL CRN"
        exit 1
    fi
    
    print_message "$GREEN" "Using IBM Cloud Logs CRN: $ICL_CRN"
    print_message "$GREEN" "IBM Cloud Logs Instance ID: $ICL_INSTANCE_ID"
    print_message "$GREEN" "IBM Cloud Logs Resource Group: $ICL_RESOURCE_GROUP"
    
    export ICL_INSTANCE_ID
}

# Function to create IAM authorization policy for IBM Cloud Logs to Event Notifications
create_iam_authorization() {
    print_message "$YELLOW" "Checking IAM authorization policy..."
    
    # Get all authorization policies
    EXISTING_AUTH=$(ibmcloud iam authorization-policies --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$EXISTING_AUTH" ]; then
        print_message "$YELLOW" "Could not retrieve existing authorization policies"
        EXISTING_AUTH="[]"
    fi
    
    # Check if there's already an authorization matching our specific ICL and EN instances
    # Look for: source service = logs, source instance = ICL_INSTANCE_ID, target service = event-notifications, target instance = EN_GUID
    AUTH_EXISTS=$(echo "$EXISTING_AUTH" | jq -r --arg icl_id "$ICL_INSTANCE_ID" --arg en_id "$EN_GUID" '
        .[] |
        select(
            (.subjects[0].attributes[] | select(.name=="serviceName") | .value) == "logs" and
            (.subjects[0].attributes[] | select(.name=="serviceInstance") | .value) == $icl_id and
            (.resources[0].attributes[] | select(.name=="serviceName") | .value) == "event-notifications" and
            (.resources[0].attributes[] | select(.name=="serviceInstance") | .value) == $en_id and
            ([.roles[].display_name] | contains(["Reader"]) and contains(["Event Source Manager"]))
        ) | .id
    ' | head -1)
    
    if [ -n "$AUTH_EXISTS" ] && [ "$AUTH_EXISTS" != "null" ]; then
        print_message "$GREEN" "IAM authorization policy already exists"
        print_message "$GREEN" "Policy ID: $AUTH_EXISTS"
        print_message "$GREEN" "Source: IBM Cloud Logs instance $ICL_INSTANCE_ID"
        print_message "$GREEN" "Target: Event Notifications instance $EN_GUID"
    else
        print_message "$YELLOW" "No matching authorization policy found"
        print_message "$YELLOW" "Creating IAM authorization policy..."
        print_message "$YELLOW" "Granting IBM Cloud Logs ($ICL_INSTANCE_ID) access to Event Notifications ($EN_GUID)..."
        
        # Create authorization policy
        # Source: IBM Cloud Logs (specific instance), Target: Event Notifications (specific instance)
        # Roles: Reader and Event Source Manager
        AUTH_OUTPUT=$(ibmcloud iam authorization-policy-create logs event-notifications "Reader,Event Source Manager" \
            --source-service-instance-id "$ICL_INSTANCE_ID" \
            --target-service-instance-id "$EN_GUID" \
            --quiet 2>&1)
        
        AUTH_EXIT_CODE=$?
        
        if [ $AUTH_EXIT_CODE -eq 0 ]; then
            print_message "$GREEN" "IAM authorization policy created successfully"
        elif echo "$AUTH_OUTPUT" | grep -q "policy_conflict_error\|409"; then
            print_message "$GREEN" "IAM authorization policy already exists with identical attributes"
            # Extract the existing policy ID from the error message
            EXISTING_POLICY_ID=$(echo "$AUTH_OUTPUT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$EXISTING_POLICY_ID" ]; then
                print_message "$GREEN" "Using existing policy ID: $EXISTING_POLICY_ID"
            fi
        else
            print_message "$RED" "Failed to create IAM authorization policy"
            print_message "$RED" "Error: $AUTH_OUTPUT"
            print_message "$YELLOW" "You may need to create it manually in the IBM Cloud console:"
            print_message "$YELLOW" "1. Go to Manage > Access (IAM) > Authorizations"
            print_message "$YELLOW" "2. Create authorization from IBM Cloud Logs to Event Notifications"
            print_message "$YELLOW" "3. Grant Reader and Event Source Manager roles"
            exit 1
        fi
    fi
}

# Function to create IBM Cloud Logs outbound integration to Event Notifications
create_icl_en_integration() {
    print_message "$YELLOW" "Creating IBM Cloud Logs outbound integration to Event Notifications..."
    
    # Construct service URL for IBM Cloud Logs API
    # Format: https://<instance-id>.api.<region>.logs.cloud.ibm.com
    ICL_SERVICE_URL="https://${ICL_INSTANCE_ID}.api.${ICL_REGION}.logs.cloud.ibm.com"
    
    print_message "$YELLOW" "Using IBM Cloud Logs service URL: $ICL_SERVICE_URL"
    
    # Set target to IBM Cloud Logs resource group and region if different from EN
    if [ "$ICL_RESOURCE_GROUP" != "$EN_RESOURCE_GROUP" ] || [ "$ICL_REGION" != "$EN_REGION" ]; then
        print_message "$YELLOW" "Switching to IBM Cloud Logs resource group: $ICL_RESOURCE_GROUP, region: $ICL_REGION"
        ibmcloud target -g "$ICL_RESOURCE_GROUP" -r "$ICL_REGION"
    else
        print_message "$GREEN" "IBM Cloud Logs and Event Notifications are in the same resource group and region"
    fi
    
    # Use EN instance name for the outbound integration name
    INTEGRATION_NAME="$SERVICE_NAME"
    
    # Check if integration already exists
    print_message "$YELLOW" "Checking for existing outbound integrations..."
    EXISTING_INTEGRATIONS=$(ibmcloud logs outgoing-webhooks --service-url "$ICL_SERVICE_URL" --output json 2>/dev/null || echo "[]")
    
    if echo "$EXISTING_INTEGRATIONS" | jq -e ".outgoing_webhooks[] | select(.name==\"$INTEGRATION_NAME\")" > /dev/null 2>&1; then
        print_message "$GREEN" "Outbound integration '$INTEGRATION_NAME' already exists."
        
        # Show the existing integration details
        print_message "$YELLOW" "Existing integration details:"
        echo "$EXISTING_INTEGRATIONS" | jq ".outgoing_webhooks[] | select(.name==\"$INTEGRATION_NAME\")"
        
        # Get the external_id which is the numeric ID needed for alerts
        INTEGRATION_ID=$(echo "$EXISTING_INTEGRATIONS" | jq -r ".outgoing_webhooks[] | select(.name==\"$INTEGRATION_NAME\") | .external_id")
        
        if [ -z "$INTEGRATION_ID" ] || [ "$INTEGRATION_ID" == "null" ]; then
            print_message "$RED" "Failed to get external_id from existing integration"
            print_message "$YELLOW" "Falling back to UUID id field"
            INTEGRATION_ID=$(echo "$EXISTING_INTEGRATIONS" | jq -r ".outgoing_webhooks[] | select(.name==\"$INTEGRATION_NAME\") | .id")
        fi
        
        print_message "$GREEN" "Using Integration ID (external_id): $INTEGRATION_ID"
    else
        # Create the outbound integration
        print_message "$YELLOW" "Creating new outbound integration with name: $INTEGRATION_NAME"
        INTEGRATION_RESPONSE=$(ibmcloud logs outgoing-webhook-create \
            --service-url "$ICL_SERVICE_URL" \
            --type "ibm_event_notifications" \
            --name "$INTEGRATION_NAME" \
            --url "null" \
            --ibm-event-notifications "{\"event_notifications_instance_id\":\"$EN_GUID\",\"region_id\":\"$EN_REGION\",\"source_id\":\"$ICL_CRN\",\"source_name\":\"$INTEGRATION_NAME\"}" \
            --output json 2>&1)
        
        if [ $? -ne 0 ]; then
            print_message "$RED" "Failed to create outbound integration"
            print_message "$RED" "Error: $INTEGRATION_RESPONSE"
            exit 1
        fi
        
        # Get the external_id which is the numeric ID needed for alerts
        INTEGRATION_ID=$(echo "$INTEGRATION_RESPONSE" | jq -r '.external_id')
        
        if [ -z "$INTEGRATION_ID" ] || [ "$INTEGRATION_ID" == "null" ]; then
            print_message "$RED" "Failed to get external_id from response"
            print_message "$YELLOW" "Response: $INTEGRATION_RESPONSE"
            exit 1
        fi
        
        print_message "$GREEN" "IBM Cloud Logs outbound integration created successfully"
        print_message "$GREEN" "Integration ID (external_id): $INTEGRATION_ID"
    fi
    
    # Export INTEGRATION_ID for use in alert creation
    export INTEGRATION_ID
    export ICL_SERVICE_URL
}

# Function to retrieve source ID from Event Notifications
get_en_source_id() {
    # Check current context before switching
    CURRENT_RG=$(ibmcloud target --output json 2>/dev/null | jq -r '.resource_group.name' 2>/dev/null || echo "")
    
    # Switch to Event Notifications resource group and region only if needed
    if [ "$CURRENT_RG" != "$EN_RESOURCE_GROUP" ]; then
        print_message "$YELLOW" "Switching to Event Notifications resource group: $EN_RESOURCE_GROUP, region: $EN_REGION"
        ibmcloud target -g "$EN_RESOURCE_GROUP" -r "$EN_REGION"
    fi
    
    # Wait a moment for the source to be created in Event Notifications
    print_message "$YELLOW" "Waiting for source to be created in Event Notifications..."
    sleep 5
    
    # Get the source ID from Event Notifications (created by IBM Cloud Logs)
    print_message "$YELLOW" "Retrieving source ID from Event Notifications..."
    SOURCES_JSON=$(ibmcloud event-notifications sources --instance-id "$EN_GUID" --output json)
    
    # Find the source that matches our IBM Cloud Logs CRN
    SOURCE_ID=$(echo "$SOURCES_JSON" | jq -r ".sources[] | select(.id | contains(\"$ICL_INSTANCE_ID\")) | .id")
    
    if [ -z "$SOURCE_ID" ] || [ "$SOURCE_ID" == "null" ]; then
        print_message "$RED" "Failed to find source in Event Notifications"
        print_message "$YELLOW" "Available sources:"
        echo "$SOURCES_JSON" | jq -r '.sources[] | "\(.id) - \(.name)"'
        exit 1
    fi
    
    print_message "$GREEN" "Found source ID in Event Notifications: $SOURCE_ID"
    
    export SOURCE_ID
}

# Combined function to create integration and alert in ICL context
create_icl_integration_and_alert() {
    # Create the outbound integration (already switches to ICL context)
    create_icl_en_integration
    
    # Create the alert (we're already in ICL context, no need to switch again)
    # The create_icl_alert function will handle context switching if needed
    create_icl_alert
    
    # Now get the source ID from Event Notifications (switches to EN context)
    get_en_source_id
}

# Function to create an alert in IBM Cloud Logs connected to the outbound integration
create_icl_alert() {
    # Build alert name with EN instance details if not explicitly set by user
    if [ "$ALERT_NAME" == "Event Notifications Alert" ]; then
        # Use default name with EN instance info
        ALERT_NAME="EN Alert - $SERVICE_NAME (${EN_GUID:0:8})"
        print_message "$YELLOW" "Using auto-generated alert name: $ALERT_NAME"
    fi
    
    print_message "$YELLOW" "Creating IBM Cloud Logs alert: $ALERT_NAME"
    
    # Note: We should already be in ICL context when called from create_icl_integration_and_alert()
    # Only switch if this function is called standalone (defensive check)
    CURRENT_RG=$(ibmcloud target --output json 2>/dev/null | jq -r '.resource_group.name' 2>/dev/null || echo "")
    if [ "$CURRENT_RG" != "$ICL_RESOURCE_GROUP" ]; then
        print_message "$YELLOW" "Switching to IBM Cloud Logs resource group: $ICL_RESOURCE_GROUP, region: $ICL_REGION"
        ibmcloud target -g "$ICL_RESOURCE_GROUP" -r "$ICL_REGION"
    fi
    
    # Validate INTEGRATION_ID before proceeding
    if [ -z "$INTEGRATION_ID" ] || [ "$INTEGRATION_ID" == "null" ]; then
        print_message "$RED" "Error: INTEGRATION_ID is not set or invalid"
        print_message "$RED" "Cannot create or check alerts without a valid integration ID"
        print_message "$YELLOW" "Please ensure the IBM Cloud Logs outbound integration was created successfully"
        exit 1
    fi
    
    # Check if alert already exists and is connected to our integration
    print_message "$YELLOW" "Checking for existing alerts connected to this integration..."
    print_message "$YELLOW" "Integration ID: $INTEGRATION_ID"
    EXISTING_ALERTS=$(ibmcloud logs alerts --service-url "$ICL_SERVICE_URL" --output json 2>/dev/null || echo "[]")
    
    # Check if an alert with the same name exists AND is connected to our specific integration_id
    ALERT_EXISTS=$(echo "$EXISTING_ALERTS" | jq -r --arg name "$ALERT_NAME" --argjson integration_id "$INTEGRATION_ID" \
        '.alerts[] | select(.name==$name and .notification_groups[].notifications[].integration_id==$integration_id) | .id' 2>&1 | head -1)
    
    # Check if jq command failed
    if echo "$ALERT_EXISTS" | grep -q "invalid JSON"; then
        print_message "$YELLOW" "Warning: Could not check for existing alerts (invalid integration_id format)"
        print_message "$YELLOW" "Proceeding to create new alert..."
        ALERT_EXISTS=""
    fi
    
    if [ -n "$ALERT_EXISTS" ] && [ "$ALERT_EXISTS" != "null" ] && ! echo "$ALERT_EXISTS" | grep -q "invalid JSON"; then
        print_message "$GREEN" "Alert '$ALERT_NAME' already exists and is connected to this integration"
        print_message "$GREEN" "Alert ID: $ALERT_EXISTS"
        ALERT_ID="$ALERT_EXISTS"
    else
        print_message "$YELLOW" "Creating new alert connected to Event Notifications integration..."
        
        # Build filters JSON with optional query parameter
        if [ -n "$ALERT_QUERY" ]; then
            print_message "$YELLOW" "Using custom query filter: $ALERT_QUERY"
            FILTERS_JSON="{\"severities\":[\"info\",\"warning\",\"error\",\"critical\"],\"text\":\"$ALERT_QUERY\",\"filter_type\":\"text_or_unspecified\"}"
        else
            print_message "$YELLOW" "Using default filter (all severities: info, warning, error, critical)"
            FILTERS_JSON='{"severities":["info","warning","error","critical"],"filter_type":"text_or_unspecified"}'
        fi
        
        # Create a simple "more than" alert that triggers when log count exceeds threshold
        # This is a basic example - users can customize the condition as needed
        
        # Validate INTEGRATION_ID before using it
        if [ -z "$INTEGRATION_ID" ] || [ "$INTEGRATION_ID" == "null" ]; then
            print_message "$RED" "Error: INTEGRATION_ID is not set or invalid"
            print_message "$RED" "Cannot create alert without a valid integration ID"
            exit 1
        fi
        
        # Build notification groups JSON with integration_id as a number
        # INTEGRATION_ID should now be the numeric external_id from the webhook
        print_message "$YELLOW" "Using numeric integration_id (external_id): $INTEGRATION_ID"
        NOTIFICATION_GROUPS=$(jq -n --argjson integration_id "$INTEGRATION_ID" \
            '[{"notifications":[{"notify_on":"triggered_and_resolved","integration_id":$integration_id}]}]' 2>&1)
        
        if [ $? -ne 0 ]; then
            print_message "$RED" "Error building notification groups JSON"
            print_message "$RED" "INTEGRATION_ID value: $INTEGRATION_ID"
            print_message "$RED" "jq error: $NOTIFICATION_GROUPS"
            exit 1
        fi
        
        print_message "$YELLOW" "Notification groups JSON:"
        echo "$NOTIFICATION_GROUPS" | jq '.'
        
        # Temporarily disable exit on error to handle alert creation failures gracefully
        set +e
        ALERT_RESPONSE=$(ibmcloud logs alert-create \
            --service-url "$ICL_SERVICE_URL" \
            --name "$ALERT_NAME" \
            --is-active=true \
            --severity "$ALERT_SEVERITY" \
            --description "Alert connected to Event Notifications - triggers when log threshold is exceeded" \
            --condition-more-than '{"parameters":{"threshold":1,"timeframe":"timeframe_5_min_or_unspecified","group_by":[],"relative_timeframe":"hour_or_unspecified"},"evaluation_window":"rolling_or_unspecified"}' \
            --filters "$FILTERS_JSON" \
            --notification-groups "$NOTIFICATION_GROUPS" \
            --output json 2>&1)
        
        ALERT_EXIT_CODE=$?
        set -e
        
        if [ $ALERT_EXIT_CODE -ne 0 ]; then
            print_message "$RED" "Failed to create alert"
            print_message "$RED" "Error: $ALERT_RESPONSE"
            print_message "$YELLOW" "You can create the alert manually in the IBM Cloud Logs console"
        else
            ALERT_ID=$(echo "$ALERT_RESPONSE" | jq -r '.id')
            
            if [ -z "$ALERT_ID" ] || [ "$ALERT_ID" == "null" ]; then
                print_message "$YELLOW" "Alert may have been created but ID not returned"
                print_message "$YELLOW" "Response: $ALERT_RESPONSE"
            else
                print_message "$GREEN" "Alert created successfully with ID: $ALERT_ID"
                print_message "$GREEN" "Alert is connected to Event Notifications integration"
            fi
        fi
    fi
    
    # Switch back to EN context if needed
    if [ "$ICL_RESOURCE_GROUP" != "$EN_RESOURCE_GROUP" ] || [ "$ICL_REGION" != "$EN_REGION" ]; then
        print_message "$YELLOW" "Switching back to Event Notifications resource group: $EN_RESOURCE_GROUP, region: $EN_REGION"
        ibmcloud target -g "$EN_RESOURCE_GROUP" -r "$EN_REGION"
    fi
    
    export ALERT_ID
}

# Function to create a topic
create_topic() {
    print_message "$YELLOW" "Creating topic: $TOPIC_NAME"
    
    # Check if topic already exists
    if ibmcloud event-notifications topics --instance-id "$EN_GUID" 2>/dev/null | grep -q "$TOPIC_NAME"; then
        print_message "$GREEN" "Topic '$TOPIC_NAME' already exists."
        TOPIC_ID=$(ibmcloud event-notifications topics --instance-id "$EN_GUID" --output json | jq -r ".topics[] | select(.name==\"$TOPIC_NAME\") | .id")
    else
        TOPIC_RESPONSE=$(ibmcloud event-notifications topic-create \
            --instance-id "$EN_GUID" \
            --name "$TOPIC_NAME" \
            --description "Topic for IBM Cloud Logs integration" \
            --output json)
        
        TOPIC_ID=$(echo "$TOPIC_RESPONSE" | jq -r '.id')
        print_message "$GREEN" "Topic created successfully with ID: $TOPIC_ID"
    fi
    
    export TOPIC_ID
}

# Function to connect IBM Cloud Logs source to topic
connect_source_to_topic() {
    print_message "$YELLOW" "Connecting IBM Cloud Logs source to topic..."
    
    # Update topic to include the source with all events enabled
    ibmcloud event-notifications topic-replace \
        --instance-id "$EN_GUID" \
        --id "$TOPIC_ID" \
        --name "$TOPIC_NAME" \
        --description "Topic connected to IBM Cloud Logs source" \
        --sources "[{\"id\":\"$SOURCE_ID\",\"rules\":[{\"enabled\":true}]}]" \
        --output json > /dev/null
    
    print_message "$GREEN" "Source connected to topic successfully (all events enabled)"
}

# Function to create a destination
create_destination() {
    if [ "$DESTINATION_TYPE" == "smtp_ibm" ]; then
        print_message "$YELLOW" "Looking for IBM Event Notifications built-in email destination..."
        
        # For smtp_ibm, a default destination is automatically created when EN instance is provisioned
        # Look for existing smtp_ibm destination
        DESTINATIONS_JSON=$(ibmcloud event-notifications destinations --instance-id "$EN_GUID" --output json)
        DESTINATION_ID=$(echo "$DESTINATIONS_JSON" | jq -r '.destinations[] | select(.type=="smtp_ibm") | .id' | head -1)
        
        if [ -n "$DESTINATION_ID" ] && [ "$DESTINATION_ID" != "null" ]; then
            DESTINATION_NAME=$(echo "$DESTINATIONS_JSON" | jq -r ".destinations[] | select(.id==\"$DESTINATION_ID\") | .name")
            print_message "$GREEN" "Found existing IBM built-in email destination: $DESTINATION_NAME"
            print_message "$GREEN" "Destination ID: $DESTINATION_ID"
        else
            print_message "$YELLOW" "No default smtp_ibm destination found, creating new one..."
            # Create IBM Event Notifications built-in email destination
            DESTINATION_RESPONSE=$(ibmcloud event-notifications destination-create \
                --instance-id "$EN_GUID" \
                --name "$DESTINATION_NAME" \
                --type "$DESTINATION_TYPE" \
                --description "IBM Event Notifications built-in email destination" \
                --output json)
            
            DESTINATION_ID=$(echo "$DESTINATION_RESPONSE" | jq -r '.id')
            print_message "$GREEN" "IBM built-in email destination created successfully with ID: $DESTINATION_ID"
        fi
    else
        print_message "$YELLOW" "Creating custom email sandbox destination: $DESTINATION_NAME"
        
        # Check if destination already exists
        if ibmcloud event-notifications destinations --instance-id "$EN_GUID" 2>/dev/null | grep -q "$DESTINATION_NAME"; then
            print_message "$GREEN" "Destination '$DESTINATION_NAME' already exists."
            DESTINATION_ID=$(ibmcloud event-notifications destinations --instance-id "$EN_GUID" --output json | jq -r ".destinations[] | select(.name==\"$DESTINATION_NAME\") | .id")
        else
            # Create custom email sandbox destination (for testing - no domain verification required)
            # For production use with custom sandbox, domain verification is needed
            DESTINATION_RESPONSE=$(ibmcloud event-notifications destination-create \
                --instance-id "$EN_GUID" \
                --name "$DESTINATION_NAME" \
                --type "$DESTINATION_TYPE" \
                --description "Custom email sandbox destination for testing" \
                --output json)
            
            DESTINATION_ID=$(echo "$DESTINATION_RESPONSE" | jq -r '.id')
            print_message "$GREEN" "Custom email sandbox destination created successfully with ID: $DESTINATION_ID"
            print_message "$YELLOW" "⚠️  IMPORTANT: Custom email sandbox is for TESTING ONLY"
            print_message "$YELLOW" "This destination type is NOT recommended for production use"
        fi
    fi
    
    export DESTINATION_ID
}

# Function to create a subscription
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
                ATTRIBUTES_JSON="{\"invited\":{\"add\":$NEW_EMAILS_JSON},\"add_notification_payload\":true,\"reply_to_mail\":\"no-reply@example.com\",\"reply_to_name\":\"Event Notifications\",\"from_name\":\"IBM Cloud Event Notifications\"}"
            else
                # For custom email sandbox
                ATTRIBUTES_JSON="{\"invited\":{\"add\":$NEW_EMAILS_JSON},\"add_notification_payload\":true,\"reply_to_mail\":\"no-reply@example.com\",\"reply_to_name\":\"Event Notifications\"}"
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
            --description "Email subscription created by provisioning script" \
            --destination-id "$DESTINATION_ID" \
            --topic-id "$TOPIC_ID" \
            --attributes "{\"invited\":$EMAIL_JSON,\"add_notification_payload\":true,\"reply_to_mail\":\"no-reply@example.com\",\"reply_to_name\":\"Event Notifications\",\"from_name\":\"IBM Cloud Event Notifications\"}" \
            --output json)
        
        SUBSCRIPTION_ID=$(echo "$SUBSCRIPTION_RESPONSE" | jq -r '.id')
        print_message "$GREEN" "✓ Subscription created for: $EMAIL_RECIPIENTS"
    fi
    
    export SUBSCRIPTION_ID
}

# Function to display summary
display_summary() {
    print_message "$GREEN" "\n=========================================="
    print_message "$GREEN" "Event Notifications Setup Complete!"
    print_message "$GREEN" "=========================================="
    echo ""
    print_message "$YELLOW" "Instance Details:"
    echo "  Service Name: $SERVICE_NAME"
    echo "  CRN: $EN_CRN"
    echo ""
    print_message "$YELLOW" "Created Resources:"
    echo "  IBM Cloud Logs CRN: $ICL_CRN"
    echo "  IBM Cloud Logs Alert ID: $ALERT_ID (connected to Event Notifications)"
    echo "  Source ID: $SOURCE_ID (created via IBM Cloud Logs outbound integration)"
    echo "  Topic ID: $TOPIC_ID (connected to source - all events enabled)"
    
    # Display destination type based on DESTINATION_TYPE variable
    if [ "$DESTINATION_TYPE" == "smtp_ibm" ]; then
        echo "  Destination ID: $DESTINATION_ID (IBM Event Notifications Built-in Email)"
    else
        echo "  Destination ID: $DESTINATION_ID (Custom Email Sandbox)"
    fi
    
    echo "  Subscription ID: $SUBSCRIPTION_ID"
    echo ""
    print_message "$YELLOW" "Email Subscription:"
    echo "  Recipients: $EMAIL_RECIPIENTS"
    echo ""
    print_message "$YELLOW" "⚠️  IMPORTANT: Email Subscription Confirmation Required"
    print_message "$YELLOW" "Email invites have been sent to: $EMAIL_RECIPIENTS"
    print_message "$YELLOW" "Each recipient must:"
    print_message "$YELLOW" "  1. Check their email inbox "
    print_message "$YELLOW" "  2. Click the confirmation link in the email"
    print_message "$YELLOW" "  3. Confirm the subscription"
    print_message "$YELLOW" "Notifications will only be sent to confirmed email addresses."
    echo ""
    print_message "$GREEN" "=========================================="
}

# Main execution
main() {
    print_message "$GREEN" "Starting Event Notifications provisioning..."
    echo ""
    
    # Initialize flag
    INSTANCE_JUST_CREATED=false
    
    # Install prerequisites
    install_ibmcloud_cli
    install_en_plugin
    install_logs_plugin
    
    # Login and setup
    login_ibmcloud
    
    # Provision instance
    provision_en_instance
    
    # Get CRN
    get_en_crn
    
    # Wait for instance to be ready (if just created)
    wait_for_instance_ready
    
    # Initialize EN CLI
    init_en_cli
    
    # Validate IBM Cloud Logs instance CRN
    validate_icl_crn
    
    # Create IAM authorization policy
    create_iam_authorization
    
    # Create IBM Cloud Logs outbound integration and alert (minimizes context switching)
    create_icl_integration_and_alert
    
    # Create resources
    create_topic
    connect_source_to_topic
    create_destination
    create_subscription
    
    # Display summary
    display_summary
    
    print_message "$GREEN" "\nScript completed successfully!"
}

# Run main function
main
