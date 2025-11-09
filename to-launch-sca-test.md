Go to portal -> vmss -> instances -> bastion -> connect via ssh, for the two instances

sudo apt update
sudo apt install -y stress-ng

stress-ng --cpu 0 --timeout 300s

stress-ng --cpu 4 --timeout 300s

wait and check the creation of new instances in the portal