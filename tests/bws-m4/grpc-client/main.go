package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/types/known/emptypb"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: grpc-client <address> <authority>")
		os.Exit(2)
	}

	address := os.Args[1]
	authority := os.Args[2]
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dialer := func(ctx context.Context, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "tcp", address)
	}
	conn, err := grpc.NewClient(
		"passthrough:///"+authority,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithContextDialer(dialer),
		grpc.WithAuthority(authority),
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "create gRPC client: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()

	if err := conn.Invoke(ctx, "/helloworld.Greeter/SayHello", &emptypb.Empty{}, &emptypb.Empty{}); err != nil {
		fmt.Fprintf(os.Stderr, "gRPC request failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("gRPC request passed")
}
