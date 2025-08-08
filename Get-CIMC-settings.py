import requests
import json
import configparser
from requests.auth import HTTPBasicAuth

# Read parameters from params-cimc.ini
config = configparser.ConfigParser()
config.read('params-cimc.ini')

# Function to create a session and retrieve manager and network settings
def get_cimc_details(cimc_ip, cimc_username, cimc_password):
    # Redfish API endpoint to create session
    session_url = f"https://{cimc_ip}/redfish/v1/SessionService/Sessions"
    
    # Credentials for login
    data = {
        "UserName": cimc_username,
        "Password": cimc_password
    }
    
    # Headers to specify content type
    headers = {
        "Content-Type": "application/json"
    }
    
    # Disable SSL warnings (if using self-signed certificates)
    requests.packages.urllib3.disable_warnings(requests.packages.urllib3.exceptions.InsecureRequestWarning)
    
    # Send POST request to create session
    response = requests.post(session_url, data=json.dumps(data), headers=headers, verify=False, auth=HTTPBasicAuth(cimc_username, cimc_password))
    
    # Check if session creation was successful
    if response.status_code == 201:
        print(f"Session created successfully for CIMC: {cimc_ip}")
        session_token = response.json().get('Token', None)
        
        # Prepare headers with session token
        headers['X-Auth-Token'] = session_token
        
        # Now, retrieve the manager details
        managers_url = f"https://{cimc_ip}/redfish/v1/Managers"
        managers_response = requests.get(managers_url, headers=headers, verify=False, auth=HTTPBasicAuth(cimc_username, cimc_password))
        
        # Collect manager details
        managers_data = {}
        if managers_response.status_code == 200:
            managers_data = managers_response.json()
        
        # Now, try accessing EthernetInterfaces for CIMC manager
        cimc_ethernet_interfaces_url = f"https://{cimc_ip}/redfish/v1/Managers/CIMC/EthernetInterfaces/NICs"
        ethernet_interfaces_data = {}
        ethernet_interfaces_response = requests.get(cimc_ethernet_interfaces_url, headers=headers, verify=False, auth=HTTPBasicAuth(cimc_username, cimc_password))
        
        if ethernet_interfaces_response.status_code == 200:
            ethernet_interfaces_data = ethernet_interfaces_response.json()
        
        # Return the data
        return {
            "cimc_ip": cimc_ip,
            "managers": managers_data,
            "ethernet_interfaces": ethernet_interfaces_data
        }
    else:
        print(f"Failed to create session for CIMC: {cimc_ip}. Status Code:", response.status_code)
        return None

# Loop through the sections in the config file (CIMC1, CIMC2, etc.)
all_cimc_data = {}

for section in config.sections():
    cimc_ip = config[section]['CIMC_IP']
    cimc_username = config[section]['CIMC_USERNAME']
    cimc_password = config[section]['CIMC_PASSWORD']
    
    # Get the CIMC details
    cimc_details = get_cimc_details(cimc_ip, cimc_username, cimc_password)
    
    if cimc_details:
        # Save the data to a dictionary with the CIMC section as the key
        all_cimc_data[section] = cimc_details

# Save the results to a JSON file
output_file = 'cimc_report.json'
with open(output_file, 'w') as json_file:
    json.dump(all_cimc_data, json_file, indent=4)

print(f"Report saved to {output_file}")
