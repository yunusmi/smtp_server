import {
  AllowNull,
  Column,
  CreatedAt,
  DataType,
  Default,
  Model,
  PrimaryKey,
  Table,
} from 'sequelize-typescript';

export type EmailStatus = 'sent' | 'failed';

@Table({
  tableName: 'email_logs',
  timestamps: true,
  updatedAt: false,
  createdAt: 'sent_at',
})
export class EmailLog extends Model<EmailLog> {
  @PrimaryKey
  @Default(DataType.UUIDV4)
  @Column(DataType.UUID)
  id: string;

  @AllowNull(false)
  @Column({ field: 'from_address', type: DataType.STRING })
  from_address: string;

  @AllowNull(false)
  @Column({ field: 'to_address', type: DataType.STRING })
  to_address: string;

  @AllowNull(true)
  @Column(DataType.STRING(998))
  subject: string;

  @AllowNull(false)
  @Default(false)
  @Column({ field: 'is_html', type: DataType.BOOLEAN })
  is_html: boolean;

  @AllowNull(false)
  @Column(DataType.ENUM('sent', 'failed'))
  status: EmailStatus;

  @AllowNull(true)
  @Column({ field: 'message_id', type: DataType.STRING })
  message_id: string;

  @AllowNull(true)
  @Column({ field: 'error_message', type: DataType.TEXT })
  error_message: string;

  @CreatedAt
  @Column({ field: 'sent_at', type: DataType.DATE })
  sent_at: Date;
}
