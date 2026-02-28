cat > init.sh << 'EOF'
#!/bin/bash
sudo apt-get update
sudo apt-get install -y apache2
EOF