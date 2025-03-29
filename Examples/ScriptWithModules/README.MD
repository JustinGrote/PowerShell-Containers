# Script with Modules

It is a best practice to bundle all your dependencies for speed and security within the module, rather than install them at runtime. As such, you should bundle your modules and any other related dependencies in your Docker container.

There are many ways to accomplish this, but I recommend doing it as part of a build step of your container.

This example uses [ModuleFast](https://github.com/JustinGrote/ModuleFast) to quickly install and embed dependencies into the module. The modules will go into the `/home/app` folder, and are specified by the `#requires` line of the script which ModuleFast can autodetect.

## Example 1: Build and Run Default Example
`docker build -t ps-network-finder .`

`docker run ps-network-finder`

*Output*: `The Network ID of 199.255.26.15/21 is 199.255.24.0`

## Example 2: Run with an Argument
`docker run ps-network-finder "/main.ps1" "10.2.1.0/8"`

*Output*: `The Network ID of 10.2.1.0/8 is 10.0.0.0`