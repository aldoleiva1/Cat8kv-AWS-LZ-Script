## Cisco Catalyst 8000V Local Zone EC2 Support Checker (aka Cat8kv-AWS-LZ-Script)


This script checks whether selected AWS Local Zones support the specific Amazon EC2 instance types required for Cisco Catalyst 8000V deployments.

It can also optionally opt in to the Local Zones listed in the script before running the support check.

## What This Script Does

The script performs two main functions:

1. Local Zone enablement check
   - Detects whether each Local Zone is already opted in.
   - Optionally enables Local Zone groups when run with `--enable-local-zones`.

2. Cisco Catalyst 8000V EC2 support validation
   - Lists EC2 instance type offerings in each Local Zone.
   - Counts available instance types by family.
   - Checks for exact Cisco Catalyst 8000V-supported EC2 instance types.

## Supported Cisco Catalyst 8000V Instance Checks

The script checks three deployment categories.

### Option A: Preferred C6in Instances

Best fit for Catalyst 8000V Local Zone deployments where available.

```bash
c6in.large
c6in.xlarge
c6in.2xlarge
c6in.8xlarge
````

### Option B: C5 and C5n Instances

Good fit where C5 or C5n is available.

```bash
c5.large
c5.xlarge
c5.2xlarge
c5.9xlarge
c5n.4xlarge
c5n.18xlarge
```

### Option C: T3 Demo or Test Instance

Useful for lightweight testing, management-plane validation, or demos.

```bash
t3.medium
```

## Requirements

You need the following before running the script:

* AWS CLI v2 installed
* AWS credentials configured
* Access to the AWS account you want to test
* IAM permissions for:

```text
ec2:DescribeAvailabilityZones
ec2:DescribeInstanceTypeOfferings
ec2:ModifyAvailabilityZoneGroup
```

`ec2:ModifyAvailabilityZoneGroup` is only required if you use the enablement option.

## File Name

Recommended script name:

```bash
v4LZ-cat8kv.sh
```

## Make the Script Executable

```bash
chmod +x v4LZ-cat8kv.sh
```

## Usage

### Check Only

This mode does not make changes to your AWS account.

```bash
./v4LZ-cat8kv.sh
```

Use this first if you only want to see which Local Zones are already enabled and whether they support Cisco Catalyst 8000V instance types.

### Enable Local Zones, Then Check

This mode enables every Local Zone listed in the script and then checks EC2 instance support.

```bash
./v4LZ-cat8kv.sh --enable-local-zones
```

## Important Warning About Enabling Local Zones

When you enable a Local Zone group, AWS opts your account into that Local Zone group.

Before enabling all zones, consider testing with one Local Zone first.

Example:

```bash
LOCAL_ZONES=(
  "Dallas|us-east-1|us-east-1-dfw-2a"
)
```

After validating the workflow, add the rest of the zones back into the `LOCAL_ZONES` array.

## Local Zones Tested by Default

The default script checks the following Local Zones:

```text
Dallas      | us-east-1 | us-east-1-dfw-2a
Chicago     | us-east-1 | us-east-1-chi-2a
New York    | us-east-1 | us-east-1-nyc-2a
Los Angeles | us-west-2 | us-west-2-lax-1a
Atlanta     | us-east-1 | us-east-1-atl-2a
Boston      | us-east-1 | us-east-1-bos-1a
Houston     | us-east-1 | us-east-1-iah-2a
Miami       | us-east-1 | us-east-1-mia-2a
```

## How to Add More Local Zones

Edit the `LOCAL_ZONES` array in the script.

Format:

```bash
"Friendly Name|AWS Region|Local Zone Name"
```

Example:

```bash
"Phoenix|us-west-2|us-west-2-phx-2a"
```

## Example Output

```text
Local Zone: Dallas
Region:     us-east-1
Zone Name:  us-east-1-dfw-2a
-------------------------------------------------------
Zone Details:
  us-east-1-dfw-2a      local-zone      us-east-1-dfw-2 opted-in        available
Group Name:
  us-east-1-dfw-2

Checking EC2 instance type offerings...

Total EC2 instance types offered in this Local Zone: 74

Family inventory:
  c6in family count: 4
    - c6in.large
    - c6in.xlarge
    - c6in.2xlarge
    - c6in.4xlarge
  c5 family count: 0
  c5n family count: 0
  t3 family count: 0

Cisco Catalyst 8000V exact instance type support check:
  Option A - Preferred C6in: SUPPORTED
    - c6in.large
    - c6in.xlarge
    - c6in.2xlarge
  Option B - C5/C5n: NOT SUPPORTED
  Option C - t3.medium demo/test: NOT SUPPORTED

RESULT: CANDIDATE - Exact Cisco Catalyst 8000V-supported EC2 type found.
```

## How to Interpret Results

### Candidate

```text
RESULT: CANDIDATE - Exact Cisco Catalyst 8000V-supported EC2 type found.
```

This means the Local Zone has at least one exact EC2 instance type that matches the Cisco Catalyst 8000V support list.

### Checked But Not Supported

```text
RESULT: CHECKED BUT NOT SUPPORTED
```

This means the Local Zone is enabled and EC2 offerings were found, but none matched the Cisco Catalyst 8000V-supported instance types in the script.

### Skipped Because Not Opted In

```text
RESULT: SKIPPED - Local Zone is not opted in.
```

This means the Local Zone was visible to your account but not enabled.

Run the script with:

```bash
./v4LZ-cat8kv.sh --enable-local-zones
```

### Warning: No EC2 Offerings Returned

```text
RESULT: WARNING - Local Zone is opted in, but no EC2 instance offerings were returned.
```

Possible causes:

* Opt-in is still propagating
* AWS account restrictions
* Temporary AWS capacity or API issue
* Incorrect region or zone mapping

## Why Exact Instance Type Matching Matters

A Local Zone may support a general instance family such as `c6in`, but Cisco Catalyst 8000V support depends on exact instance types.

For example:

```text
c6in.large       supported
c6in.xlarge      supported
c6in.2xlarge     supported
c6in.4xlarge     not listed in the script
```

Do not assume the whole family is supported just because one family member appears.

## Recommended Deployment Decision Logic

Use this decision flow:

```text
1. Is the Local Zone opted in?
   - No: enable it or skip it.
   - Yes: continue.

2. Are EC2 instance offerings returned?
   - No: wait, verify account access, or check AWS zone mapping.
   - Yes: continue.

3. Is an exact Cisco Catalyst 8000V-supported EC2 type available?
   - Yes: candidate Local Zone.
   - No: not currently suitable for Catalyst 8000V.
```

## Troubleshooting

### The Script Stops Early

Make sure the script uses this counter format:

```bash
checked_count=$((checked_count + 1))
```

Avoid this format when using `set -e`:

```bash
((checked_count++))
```

That can cause Bash to exit when the previous value is `0`.

### All Local Zones Show Zero Instance Types

Check whether the Local Zones are opted in.

Run:

```bash
aws ec2 describe-availability-zones \
  --region us-east-1 \
  --all-availability-zones \
  --filters "Name=zone-type,Values=local-zone" \
  --query "AvailabilityZones[*].[ZoneName,GroupName,OptInStatus,State]" \
  --output table
```

If they show `not-opted-in`, run the script with:

```bash
./v4LZ-cat8kv.sh --enable-local-zones
```

### A Local Zone Is Enabled But Still Shows No EC2 Offerings

Wait a few minutes and rerun the script.

If the issue remains, validate manually:

```bash
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=location,Values=us-east-1-dfw-2a" \
  --region us-east-1 \
  --output table
```

## Safety Notes

* The default check mode makes no changes.
* The `--enable-local-zones` mode modifies your AWS account by opting in to the Local Zone groups listed in the script.
* Review the `LOCAL_ZONES` array before running with enablement.
* Enabling a Local Zone does not deploy infrastructure by itself.
* Actual Catalyst 8000V deployment still requires AMI availability, networking configuration, licensing, security groups, IAM, routing, and deployment validation.

