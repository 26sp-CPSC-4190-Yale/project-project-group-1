### Getting Started

#### Clone the repo onto a Mac with xcode

`git clone https://github.com/26sp-CPSC-4190-Yale/project-project-group-1.git'

#### The Server

The server is already spun up on an ec2 and the Ios app directly calls unplugged.name, but if you wanted to start the server use the dockerfile as follows:

'cd Unplugged/Docker'
'docker compose up --build -d'

#### The Client

Go into xcode and connect your target and run the Unplugged ios app.
