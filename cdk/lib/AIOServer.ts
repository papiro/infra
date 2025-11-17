import { CfnOutput, Duration, Stack, StackProps } from "aws-cdk-lib";
import { Construct } from "constructs";
import {
  Vpc,
  Instance,
  SecurityGroup,
  Peer,
  Port,
  BlockDeviceVolume,
  CfnEIP,
  CfnEIPAssociation,
  EbsDeviceVolumeType,
  InstanceType,
  KeyPair,
  MachineImage,
  SubnetType,
  AmazonLinuxCpuType,
} from "aws-cdk-lib/aws-ec2";
import { ARecord, HostedZone, RecordTarget } from "aws-cdk-lib/aws-route53";
import {
  Role,
  ServicePrincipal,
  ManagedPolicy,
  PolicyStatement,
  Effect,
  PolicyDocument,
} from "aws-cdk-lib/aws-iam";
import { Bucket } from "aws-cdk-lib/aws-s3";

export interface AppDefinition {
  id: string;
  domains: string[];
  port: number;
}

export interface AIOServerStackProps extends StackProps {
  vpc: Vpc;
  /** Public domains that should resolve to the AIO server */
  apps?: AppDefinition[];
  keyPairName: string;
  imageS3Bucket: Bucket;
  userData?: string[];
  instanceType?: string;
  inlinePolicies?: Record<string, PolicyDocument>;
}

export class AIOServer extends Construct {
  public readonly instance: Instance;
  public readonly securityGroup: SecurityGroup;

  constructor(
    scope: Construct,
    id: string,
    {
      vpc,
      apps = [],
      keyPairName,
      imageS3Bucket,
      userData = [],
      instanceType = "t4g.small",
      inlinePolicies,
      ...props
    }: AIOServerStackProps
  ) {
    super(scope, id);

    const securityGroup = new SecurityGroup(this, "SecurityGroup", {
      vpc,
      description: "AIOServer security group",
      allowAllOutbound: true,
    });

    securityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(80),
      "HTTP from internet"
    );

    securityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(443),
      "HTTPS from internet"
    );

    const instance = new Instance(this, "Instance", {
      vpc,
      vpcSubnets: { subnetType: SubnetType.PUBLIC },
      instanceType: new InstanceType(instanceType),
      machineImage: MachineImage.latestAmazonLinux2023({
        cpuType: AmazonLinuxCpuType.ARM_64,
        cachedInContext: true,
      }),
      securityGroup: securityGroup,
      role: new Role(this, "IncubatorAppServerRole", {
        assumedBy: new ServicePrincipal("ec2.amazonaws.com"),
        managedPolicies: [
          ManagedPolicy.fromAwsManagedPolicyName(
            "AmazonSSMManagedInstanceCore"
          ),
          ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy"),
        ],
        inlinePolicies,
      }),
      keyPair: KeyPair.fromKeyPairName(this, "KeyPair", keyPairName),
      blockDevices: [
        {
          deviceName: "/dev/xvda",
          volume: BlockDeviceVolume.ebs(20, {
            volumeType: EbsDeviceVolumeType.GP3,
            deleteOnTermination: false,
            encrypted: true,
          }),
        },
      ],
    });

    instance.addUserData(
      "dnf update -y",
      ...userData,
      "dnf install -y amazon-cloudwatch-agent",
      'echo "UserData complete"'
    );

    // Allocate Elastic IP and associate with instance for stable public address
    const eip = new CfnEIP(this, "Eip", {
      domain: "vpc",
    });

    new CfnEIPAssociation(this, "CfnEipAssociation", {
      allocationId: eip.attrAllocationId,
      instanceId: instance.instanceId,
    });

    new CfnOutput(this, "AIOServerElasticIp", {
      value: eip.attrPublicIp,
      description: "Elastic IP of the AIO Server",
      exportName: "AIOServerEip",
    });

    new CfnOutput(this, "AIOServerInstanceId", {
      value: instance.instanceId,
      exportName: "AIOServerInstanceId",
    });

    // Public DNS records per incubated application
    apps.forEach((appDef) => {
      const publicZone = HostedZone.fromLookup(
        this,
        `${appDef.id}-PublicZone`,
        {
          domainName: appDef.domains[0].split(".").slice(1).join("."),
        }
      );

      appDef.domains.forEach((domain) => {
        new ARecord(this, `ARecord-${domain}`, {
          zone: publicZone,
          recordName: domain.replace(`.${publicZone.zoneName}`, ""),
          target: RecordTarget.fromIpAddresses(instance.instancePublicIp),
          ttl: Duration.minutes(1),
        });
      });
    });

    this.instance = instance;
    this.securityGroup = securityGroup;
  }
}
