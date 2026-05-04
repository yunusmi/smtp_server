import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/sequelize';
import { EmailLog } from '../entities/email-log.entity';
import { MailerService } from './mailer.service';
import {
  SendEmailDto,
  SendEmailResponseDto,
  SendEmailResultItem,
} from '../dto/send-email.dto';

@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);

  constructor(
    private readonly mailerService: MailerService,
    private readonly configService: ConfigService,
    @InjectModel(EmailLog) private readonly emailLogModel: typeof EmailLog,
  ) {}

  async send(dto: SendEmailDto): Promise<SendEmailResponseDto> {
    const from_address = this.configService.get<string>('MAIL_FROM');
    const recipients = Array.from(new Set(dto.emails.map((e) => e.trim())));
    const results: SendEmailResultItem[] = [];

    for (const to of recipients) {
      try {
        const { message_id } = await this.mailerService.sendMail({
          from: from_address,
          to,
          subject: dto.subject,
          body: dto.body,
          is_html: dto.is_html,
        });
        await this.emailLogModel.create({
          from_address,
          to_address: to,
          subject: dto.subject ?? null,
          is_html: dto.is_html,
          status: 'sent',
          message_id,
        } as EmailLog);
        results.push({ email: to, status: 'sent', message_id });
      } catch (err) {
        const error_message = err?.message ?? String(err);
        this.logger.warn(`Failed to send to ${to}: ${error_message}`);
        await this.emailLogModel.create({
          from_address,
          to_address: to,
          subject: dto.subject ?? null,
          is_html: dto.is_html,
          status: 'failed',
          error_message,
        } as EmailLog);
        results.push({ email: to, status: 'failed', error: error_message });
      }
    }

    const sent = results.filter((r) => r.status === 'sent').length;
    return {
      total: results.length,
      sent,
      failed: results.length - sent,
      results,
    };
  }
}
