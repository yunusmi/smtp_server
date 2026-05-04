import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
import { Transporter } from 'nodemailer';

export interface SendMailOptions {
  from: string;
  to: string;
  subject?: string;
  body: string;
  is_html: boolean;
}

@Injectable()
export class MailerService implements OnModuleInit {
  private readonly logger = new Logger(MailerService.name);
  private transporter: Transporter;

  constructor(private readonly configService: ConfigService) {}

  onModuleInit(): void {
    const host = this.configService.get<string>('SMTP_HOST', '127.0.0.1');
    const port = parseInt(
      this.configService.get<string>('SMTP_PORT', '25'),
      10,
    );
    const secure =
      this.configService.get<string>('SMTP_SECURE', 'false') === 'true';

    this.transporter = nodemailer.createTransport({
      host,
      port,
      secure,
      tls: { rejectUnauthorized: false },
    });

    this.transporter
      .verify()
      .then(() =>
        this.logger.log(
          `SMTP transport ready (${host}:${port}, secure=${secure})`,
        ),
      )
      .catch((err) =>
        this.logger.error(
          `SMTP transport verification failed: ${err.message}`,
        ),
      );
  }

  async sendMail(options: SendMailOptions): Promise<{ message_id: string }> {
    const info = await this.transporter.sendMail({
      from: options.from,
      to: options.to,
      subject: options.subject,
      [options.is_html ? 'html' : 'text']: options.body,
    });
    return { message_id: info.messageId };
  }
}
