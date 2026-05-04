import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { EmailController } from './email.controller';
import { EmailService } from './services/email.service';
import { MailerService } from './services/mailer.service';
import { EmailLog } from './entities/email-log.entity';

@Module({
  imports: [SequelizeModule.forFeature([EmailLog])],
  controllers: [EmailController],
  providers: [EmailService, MailerService],
})
export class EmailModule {}
