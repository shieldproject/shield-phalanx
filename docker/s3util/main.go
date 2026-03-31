package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

func fatal(msg string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, msg+"\n", args...)
	os.Exit(1)
}

func env(name, fallback string) string {
	v := os.Getenv(name)
	if v == "" {
		return fallback
	}
	return v
}

func requireEnv(name string) string {
	v := os.Getenv(name)
	if v == "" {
		fatal("required environment variable %s is not set", name)
	}
	return v
}

func newClient(ctx context.Context) *s3.Client {
	endpoint := os.Getenv("S3_ENDPOINT")
	region := env("AWS_REGION", "us-east-1")
	accessKey := requireEnv("AWS_ACCESS_KEY_ID")
	secretKey := requireEnv("AWS_SECRET_ACCESS_KEY")

	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(region),
		config.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(accessKey, secretKey, ""),
		),
	)
	if err != nil {
		fatal("failed to load AWS config: %v", err)
	}

	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
		o.UsePathStyle = true // Required for RustFS/MinIO
	})

	return client
}

func createBucket(ctx context.Context, client *s3.Client, bucket string) {
	_, err := client.CreateBucket(ctx, &s3.CreateBucketInput{
		Bucket: aws.String(bucket),
	})
	if err != nil {
		// Ignore "BucketAlreadyOwnedByYou" for idempotency
		var alreadyOwned *types.BucketAlreadyOwnedByYou
		if errors.As(err, &alreadyOwned) {
			fmt.Printf("bucket %q already exists (owned by you)\n", bucket)
			return
		}
		fatal("failed to create bucket %q: %v", bucket, err)
	}
	fmt.Printf("bucket %q created\n", bucket)
}

func deleteBucket(ctx context.Context, client *s3.Client, bucket string) {
	// List and delete all objects (paginated)
	paginator := s3.NewListObjectsV2Paginator(client, &s3.ListObjectsV2Input{
		Bucket: aws.String(bucket),
	})

	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			fatal("failed to list objects in bucket %q: %v", bucket, err)
		}

		if len(page.Contents) == 0 {
			continue
		}

		// Build delete batch (max 1000 per call)
		objects := make([]types.ObjectIdentifier, 0, len(page.Contents))
		for _, obj := range page.Contents {
			objects = append(objects, types.ObjectIdentifier{
				Key: obj.Key,
			})
		}

		// Delete in batches of 1000
		for i := 0; i < len(objects); i += 1000 {
			end := i + 1000
			if end > len(objects) {
				end = len(objects)
			}
			batch := objects[i:end]

			_, err := client.DeleteObjects(ctx, &s3.DeleteObjectsInput{
				Bucket: aws.String(bucket),
				Delete: &types.Delete{
					Objects: batch,
					Quiet:   aws.Bool(true),
				},
			})
			if err != nil {
				fatal("failed to delete objects from bucket %q: %v", bucket, err)
			}
			fmt.Printf("deleted %d objects from bucket %q\n", len(batch), bucket)
		}
	}

	// Delete the now-empty bucket
	_, err := client.DeleteBucket(ctx, &s3.DeleteBucketInput{
		Bucket: aws.String(bucket),
	})
	if err != nil {
		fatal("failed to delete bucket %q: %v", bucket, err)
	}
	fmt.Printf("bucket %q deleted\n", bucket)
}

func getObject(ctx context.Context, client *s3.Client, bucket, key, dest string) {
	resp, err := client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		fatal("failed to get object %q from bucket %q: %v", key, bucket, err)
	}
	defer resp.Body.Close()

	f, err := os.Create(dest)
	if err != nil {
		fatal("failed to create file %q: %v", dest, err)
	}
	defer f.Close()

	n, err := io.Copy(f, resp.Body)
	if err != nil {
		fatal("failed to write to file %q: %v", dest, err)
	}
	fmt.Printf("downloaded %q to %q (%d bytes)\n", key, dest, n)
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage:\n")
	fmt.Fprintf(os.Stderr, "  s3util create-bucket\n")
	fmt.Fprintf(os.Stderr, "  s3util delete-bucket\n")
	fmt.Fprintf(os.Stderr, "  s3util get <key> <dest>\n")
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	ctx := context.Background()
	client := newClient(ctx)
	bucket := requireEnv("S3_BUCKET")

	switch os.Args[1] {
	case "create-bucket":
		createBucket(ctx, client, bucket)

	case "delete-bucket":
		deleteBucket(ctx, client, bucket)

	case "get":
		if len(os.Args) != 4 {
			fmt.Fprintf(os.Stderr, "Usage: s3util get <key> <dest>\n")
			os.Exit(1)
		}
		key := os.Args[2]
		dest := os.Args[3]
		getObject(ctx, client, bucket, key, dest)

	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		usage()
	}
}
