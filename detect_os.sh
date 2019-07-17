OS=$(uname -a)
if [[ OS == *ubuntu* ]]; then
  echo Ubuntu
else
  echo "Red Hat OS"
fi
