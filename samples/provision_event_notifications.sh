#!/bin/bash

# =================================================
# IBM Cloud Event Notifications Provisioning Script
# =================================================
# This script provisions an Event Notifications instance and creates Event Notifications topic,
#  source, destination, and subscription
#
# PREREQUISITES:
# 1. Make the script executable:
#    chmod +x provision_event_notifications.sh
#
# 2. Login to IBM Cloud account using CLI:
#    ibmcloud login --sso
#    OR
#    ibmcloud login --apikey <your-api-key>
#
# 3. Account Requirements:
#    - By default, this script creates a LITE plan instance (free tier)
#    - RECOMMENDED: Use STANDARD plan for production workloads (requires Pay-As-You-Go account)
#    - To use STANDARD plan, set PLAN variable to "standard"
#    - Note: LITE plan has limited features and is suitable for testing only
#
# 4. Run the script:
#    ./provision_event_notifications.sh
#
# CONFIGURATION VARIABLES:
# You can customize the script behavior by setting environment variables before running:
#
#   RESOURCE_GROUP       - IBM Cloud resource group (default: Default)
#   REGION              - IBM Cloud region (default: us-south)
#   SERVICE_NAME        - Name of Event Notifications instance (default: my-event-notifications)
#   PLAN                - Service plan: lite or standard (default: lite, RECOMMENDED: standard for production)
#   SERVICE_ENDPOINTS   - Endpoint type: public, private, or public-and-private (default: public-and-private)
#   TOPIC_NAME          - Name of the topic (default: my-topic)
#   SOURCE_NAME         - Name of the API source (default: my-api-source)
#   DESTINATION_NAME    - Name of the destination (default: my-destination)
#   SUBSCRIPTION_NAME   - Name of the subscription (default: my-subscription)
#   DESTINATION_TYPE    - Type of destination (default: webhook)
#   WEBHOOK_URL         - Webhook URL for destination (default: https://example.com/webhook)
#
# EXAMPLE USAGE WITH CUSTOM VARIABLES:
#   export RESOURCE_GROUP="production"
#   export REGION="eu-gb"
#   export SERVICE_NAME="prod-event-notifications"
#   export WEBHOOK_URL="https://myapp.com/webhook"
#   export PLAN="standard"
#   ./provision_event_notifications.sh
#
# ==========================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
RESOURCE_GROUP="${RESOURCE_GROUP:-Default}"
REGION="${REGION:-us-south}"
SERVICE_NAME="${SERVICE_NAME:-my-event-notifications}"
PLAN="${PLAN:-lite}"
SERVICE_ENDPOINTS="${SERVICE_ENDPOINTS:-public-and-private}"
TOPIC_NAME="${TOPIC_NAME:-my-topic}"
SOURCE_NAME="${SOURCE_NAME:-my-api-source}"
DESTINATION_NAME="${DESTINATION_NAME:-my-destination}"
SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-my-subscription}"
DESTINATION_TYPE="${DESTINATION_TYPE:-webhook}"
WEBHOOK_URL="${WEBHOOK_URL:-https://example.com/webhook}"

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
        ibmcloud plugin show event-notifications
        
        # Check for updates
        print_message "$YELLOW" "Checking for plugin updates..."
        ibmcloud plugin update event-notifications -f
    else
        print_message "$YELLOW" "Installing Event Notifications CLI plugin..."
        ibmcloud plugin install event-notifications -f
        print_message "$GREEN" "Event Notifications plugin installed successfully."
    fi
}

# Function to login to IBM Cloud
login_ibmcloud() {
    print_message "$YELLOW" "Checking IBM Cloud login status..."
    
    if ibmcloud target >/dev/null 2>&1; then
        print_message "$GREEN" "Already logged in to IBM Cloud."
    else
        print_message "$YELLOW" "Please login to IBM Cloud..."
        ibmcloud login --sso
    fi
    
    # Set target resource group and region
    print_message "$YELLOW" "Setting target resource group: $RESOURCE_GROUP and region: $REGION"
    ibmcloud target -g "$RESOURCE_GROUP" -r "$REGION"
}

# Function to provision Event Notifications instance
provision_en_instance() {
    print_message "$YELLOW" "Checking if Event Notifications instance exists..."
    
    if ibmcloud resource service-instance "$SERVICE_NAME" >/dev/null 2>&1; then
        print_message "$GREEN" "Event Notifications instance '$SERVICE_NAME' already exists."
    else
        print_message "$YELLOW" "Provisioning Event Notifications instance: $SERVICE_NAME"
        print_message "$YELLOW" "Service endpoints: $SERVICE_ENDPOINTS"
        
        # Create the instance with service endpoints parameter
        if [ "$PLAN" == "lite" ]; then
            # Lite plan may not support service endpoints parameter
            ibmcloud resource service-instance-create "$SERVICE_NAME" \
                event-notifications "$PLAN" "$REGION" \
                -g "$RESOURCE_GROUP"
        else
            # Standard plan with service endpoints
            ibmcloud resource service-instance-create "$SERVICE_NAME" \
                event-notifications "$PLAN" "$REGION" \
                -g "$RESOURCE_GROUP" \
                --service-endpoints "$SERVICE_ENDPOINTS"
        fi
        
        print_message "$GREEN" "Event Notifications instance provisioned successfully."
        
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

# Function to initialize Event Notifications CLI
init_en_cli() {
    print_message "$YELLOW" "Initializing Event Notifications CLI with instance..."
    ibmcloud event-notifications init --instance-id "$EN_GUID"
    print_message "$GREEN" "Event Notifications CLI initialized successfully."
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
            --description "Topic created by provisioning script" \
            --output json)
        
        TOPIC_ID=$(echo "$TOPIC_RESPONSE" | jq -r '.id')
        print_message "$GREEN" "Topic created successfully with ID: $TOPIC_ID"
    fi
    
    export TOPIC_ID
}

# Function to create an API source
create_api_source() {
    print_message "$YELLOW" "Creating API source: $SOURCE_NAME"
    
    # Check if source already exists
    if ibmcloud event-notifications sources --instance-id "$EN_GUID" 2>/dev/null | grep -q "$SOURCE_NAME"; then
        print_message "$GREEN" "API source '$SOURCE_NAME' already exists."
        SOURCE_ID=$(ibmcloud event-notifications sources --instance-id "$EN_GUID" --output json | jq -r ".sources[] | select(.name==\"$SOURCE_NAME\") | .id")
    else
        SOURCE_RESPONSE=$(ibmcloud event-notifications sources-create \
            --instance-id "$EN_GUID" \
            --name "$SOURCE_NAME" \
            --description "API source created by provisioning script" \
            --enabled true \
            --output json)
        
        SOURCE_ID=$(echo "$SOURCE_RESPONSE" | jq -r '.id')
        print_message "$GREEN" "API source created successfully with ID: $SOURCE_ID"
    fi
    
    export SOURCE_ID
}

# Function to create a destination
create_destination() {
    print_message "$YELLOW" "Creating destination: $DESTINATION_NAME"
    
    # Check if destination already exists
    if ibmcloud event-notifications destinations --instance-id "$EN_GUID" 2>/dev/null | grep -q "$DESTINATION_NAME"; then
        print_message "$GREEN" "Destination '$DESTINATION_NAME' already exists."
        DESTINATION_ID=$(ibmcloud event-notifications destinations --instance-id "$EN_GUID" --output json | jq -r ".destinations[] | select(.name==\"$DESTINATION_NAME\") | .id")
    else
        # Create webhook destination with proper config structure
        DESTINATION_RESPONSE=$(ibmcloud event-notifications destination-create \
            --instance-id "$EN_GUID" \
            --name "$DESTINATION_NAME" \
            --type "$DESTINATION_TYPE" \
            --description "Webhook destination created by provisioning script" \
            --config "{\"params\":{\"url\":\"$WEBHOOK_URL\",\"verb\":\"POST\"}}" \
            --output json)
        
        DESTINATION_ID=$(echo "$DESTINATION_RESPONSE" | jq -r '.id')
        print_message "$GREEN" "Destination created successfully with ID: $DESTINATION_ID"
    fi
    
    export DESTINATION_ID
}

# Function to create a subscription
create_subscription() {
    print_message "$YELLOW" "Creating subscription: $SUBSCRIPTION_NAME"
    
    # Check if subscription already exists
    if ibmcloud event-notifications subscriptions --instance-id "$EN_GUID" 2>/dev/null | grep -q "$SUBSCRIPTION_NAME"; then
        print_message "$GREEN" "Subscription '$SUBSCRIPTION_NAME' already exists."
        SUBSCRIPTION_ID=$(ibmcloud event-notifications subscriptions --instance-id "$EN_GUID" --output json | jq -r ".subscriptions[] | select(.name==\"$SUBSCRIPTION_NAME\") | .id")
    else
        SUBSCRIPTION_RESPONSE=$(ibmcloud event-notifications subscription-create \
            --instance-id "$EN_GUID" \
            --name "$SUBSCRIPTION_NAME" \
            --description "Subscription created by provisioning script" \
            --destination-id "$DESTINATION_ID" \
            --topic-id "$TOPIC_ID" \
            --output json)
        
        SUBSCRIPTION_ID=$(echo "$SUBSCRIPTION_RESPONSE" | jq -r '.id')
        print_message "$GREEN" "Subscription created successfully with ID: $SUBSCRIPTION_ID"
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
    echo "  Topic ID: $TOPIC_ID"
    echo "  Source ID: $SOURCE_ID"
    echo "  Destination ID: $DESTINATION_ID"
    echo "  Subscription ID: $SUBSCRIPTION_ID"
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
    
    # Create resources
    create_topic
    create_api_source
    create_destination
    create_subscription
    
    # Display summary
    display_summary
    
    print_message "$GREEN" "\nScript completed successfully!"
}

# Run main function
main
