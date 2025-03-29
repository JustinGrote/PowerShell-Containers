# Run from Script
In this folder is a script and a Dockerfile that instructs it to include the container at the root level.

1. Build the container (make sure you are in this same directory, or otherwise specify the path rather than `.`)

	`docker build -t pshello .` (you can replace `pshello` tag with whatever you want)

1. Run the container. The entrypoint is already specified in the container via the `CMD` operator in the dockerfile.

	`docker run pshello`
	
	*Output:* ```Hello world at 03/29/2025 21:08:05!```
	
1. Now try running the container with an argument. You must respecify the `CMD` part as the first argument when doing this

	`docker run pshello "/main.ps1" "Friend"`
	
	*Output:* ```Hello Friend at 03/29/2025 21:08:05!```