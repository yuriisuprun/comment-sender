package handler;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.simpleemail.AmazonSimpleEmailService;
import com.amazonaws.services.simpleemail.AmazonSimpleEmailServiceClientBuilder;
import com.amazonaws.services.simpleemail.model.*;

import java.util.Map;

public class CommentHandler implements RequestHandler<Map<String, Object>, Map<String, String>> {

    private static final String ADMIN_EMAIL = System.getenv("ADMIN_EMAIL");
    private static final String FROM_EMAIL = System.getenv("FROM_EMAIL");

    @Override
    public Map<String, String> handleRequest(Map<String, Object> input, Context context) {
        String comment = (String) input.get("comment");
        context.getLogger().log("Received comment: " + comment);

        try {
            context.getLogger().log("Preparing to send email to: " + ADMIN_EMAIL);
            sendEmail(comment, context);
            context.getLogger().log("Email sent successfully to: " + ADMIN_EMAIL);
            return Map.of("message", "Comment sent successfully!");
        } catch (Exception e) {
            context.getLogger().log("Exception while sending email: " + e.getMessage());
            return Map.of("message", "Failed to send comment.");
        }
    }

    private void sendEmail(String comment, Context context) {
        AmazonSimpleEmailService client = AmazonSimpleEmailServiceClientBuilder.standard()
                .withRegion(System.getenv("DEFAULT_REGION"))
                .build();

        SendEmailRequest request = new SendEmailRequest()
                .withDestination(new Destination().withToAddresses(ADMIN_EMAIL))
                .withMessage(new Message()
                        .withSubject(new Content().withCharset("UTF-8").withData("New User Comment"))
                        .withBody(new Body().withText(new Content().withCharset("UTF-8").withData(comment))))
                .withSource(FROM_EMAIL);

        try {
            context.getLogger().log("Sending email request...");
            SendEmailResult result = client.sendEmail(request);
            context.getLogger().log("SES message ID: " + result.getMessageId());
            context.getLogger().log("Send email request completed.");
        } catch (Exception e) {
            context.getLogger().log("SES error: " + e.getMessage());
            throw e;
        }
    }
}
