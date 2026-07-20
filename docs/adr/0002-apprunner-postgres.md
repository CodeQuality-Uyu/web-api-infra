# 0002 — App Runner + Postgres for compute

**Status:** Accepted

The web API runs on AWS App Runner (managed HTTPS, autoscaling, self-managed TLS for the
custom domain) reaching a private RDS Postgres via a VPC connector. Removes the ALB, ECS
cluster, and host-routing layers — fewer pieces to deploy a "web API + Postgres + domain".

Trade-offs: no ECS Exec / RunTask (migrations run via CodeBuild-in-VPC, see 0005); less
routing flexibility than ALB+ECS. The `service` module is isolated so a swap back to ECS
would not touch the rest of the tree. Revisit if App Runner's roadmap stalls.
