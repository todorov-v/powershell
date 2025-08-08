import requests
import json
import configparser
from requests.auth import HTTPBasicAuth

# Read parameters from params-cimc.ini
config = configparser.ConfigParser()
config.read('params-cimc.ini')

# Function to create a session and set DNS details
def set_dns_details(cimc_ip, cimc_username, cimc_password, dns_servers):
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
        
        # Now, update the DNS details for the NIC
        network_url = f"https://{cimc_ip}/redfish/v1/Managers/CIMC/EthernetInterfaces/NICs"
        
        # Prepare the payload with DNS and other network details
        payload = {
            "Oem": {
                "Cisco": {
                    "IPv6Enabled": False,
                    "DynamicDNS": {
                        "Enabled": True,
                        "RefreshInterval": 0
                    },
                    "NetworkPortProperties": {
                        "OperationModeFullDuplex": True,
                        "OperationModePortSpeed": 1024
                    },
                    "NICProperties": {
                        "NICRedundancy": "None",
                        "NICMode": "Dedicated",
                        "VICSlot": "None"
                    }
                }
            },
            "NameServers": dns_servers,
            "StatelessAddressAutoConfig": {
                "IPv6AutoConfigEnabled": False,
                "IPv4AutoConfigEnabled": False
            },
            "Id": "NICs",
            "Name": "Manager Ethernet Interface",
            "StaticNameServers": dns_servers
        }
        
        # Send the PATCH request to update the network settings
        patch_response = requests.patch(network_url, data=json.dumps(payload), headers=headers, verify=False, auth=HTTPBasicAuth(cimc_username, cimc_password))
        
        # Check if update was successful
        if patch_response.status_code == 200:
            print(f"DNS and network settings updated successfully for CIMC: {cimc_ip}")
        else:
            print(f"Failed to update DNS settings for CIMC: {cimc_ip}. Status Code:", patch_response.status_code)
            print("Error:", patch_response.text)
        
    else:
        print(f"Failed to create session for CIMC: {cimc_ip}. Status Code:", response.status_code)

# Loop through the sections in the config file (CIMC1, CIMC2, etc.)
for section in config.sections():
    cimc_ip = config[section]['CIMC_IP']
    cimc_username = config[section]['CIMC_USERNAME']
    cimc_password = config[section]['CIMC_PASSWORD']
    
    # Extract DNS details from the ini file
    dns_servers = [
        config[section]['DNS1'],
        config[section]['DNS2'],
        config[section]['DNS3']
    ]
    
    # Set DNS details for the CIMC
    set_dns_details(cimc_ip, cimc_username, cimc_password, dns_servers)
