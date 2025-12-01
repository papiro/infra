import { Construct } from "constructs";
import { AIOServer } from "./AIOServer";
import {
  ARecord,
  HostedZone,
  IHostedZone,
  RecordTarget,
} from "aws-cdk-lib/aws-route53";
import { Duration } from "aws-cdk-lib";

export interface AIOServerRecordProps {
  aioserver: AIOServer;
  domain: string;
  hostedZone?: IHostedZone;
}

export class AIOServerRecord extends Construct {
  constructor(
    scope: Construct,
    id: string,
    { aioserver, domain, hostedZone }: AIOServerRecordProps
  ) {
    super(scope, id);

    const publicZone =
      hostedZone ??
      HostedZone.fromLookup(this, `${domain}-PublicZone`, {
        domainName: domain,
      });

    new ARecord(this, `ARecord-${domain}`, {
      zone: publicZone,
      recordName: domain.replace(`.${publicZone.zoneName}`, ""),
      target: RecordTarget.fromIpAddresses(aioserver.instance.instancePublicIp),
      ttl: Duration.minutes(1),
    });

    new ARecord(this, `WWW-ARecord-${domain}`, {
      zone: publicZone,
      recordName: `www.${domain.replace(`.${publicZone.zoneName}`, "")}`,
      target: RecordTarget.fromIpAddresses(aioserver.instance.instancePublicIp),
      ttl: Duration.minutes(1),
    });
  }
}
